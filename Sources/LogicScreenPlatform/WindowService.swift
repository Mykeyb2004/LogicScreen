import AppKit
import ApplicationServices
import Foundation
import LogicScreenCore
import OSLog
import QuartzCore

/// Accessibility IPC runs on this actor rather than blocking the UI thread.
public actor WindowService {
    private struct SavedWindow {
        let element: AXUIElement
        let frame: CGRect
        let displayIdentity: String?
    }
    private struct SavedLocalWindow: Sendable {
        let windowNumber: Int
        let frame: CGRect
        let displayIdentity: String?
    }
    private struct LocalGatherOutcome: Sendable {
        var report = MigrationReport()
        var saved: [SavedLocalWindow]
        var migratedWindowNumbers: [Int] = []
    }
    private struct LocalRestoreOutcome: Sendable {
        var report = MigrationReport()
        var remaining: [SavedLocalWindow] = []
    }

    private var saved: [SavedWindow] = []
    private var savedLocal: [SavedLocalWindow] = []
    private var lastMigrated: [AXUIElement] = []
    private var lastMigratedLocal: [Int] = []
    private let logger = Logger(subsystem: "dev.logicscreen.app", category: "Windows")

    public init() {}

    public func inventory(displays: [DisplayRecord], pids: [pid_t]) async throws -> WindowInventory {
        guard AXIsProcessTrusted() else { throw ScreenOperationError.permissionRequired }
        var result = WindowInventory()
        let selfPID = getpid()
        for pid in pids {
            if pid == selfPID {
                let local = await Self.localInventory(pid: pid, displays: displays)
                result.windows.append(contentsOf: local)
                continue
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.4)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
                result.unreadablePIDs.append(pid)
                continue
            }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.4)
                guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole,
                      let rect = frame(window), rect.width > 1, rect.height > 1,
                      let display = WindowPlacement.owningDisplay(for: rect, displays: displays) else { continue }
                let restriction: WindowRestriction?
                if bool(window, kAXMinimizedAttribute) { restriction = .minimized }
                else if bool(window, "AXFullScreen") { restriction = .fullScreen }
                else if !settable(window, kAXPositionAttribute) { restriction = .fixed }
                else { restriction = nil }
                result.windows.append(WindowPreview(applicationPID: pid, displayID: display.id, restriction: restriction))
            }
        }
        return result
    }

    public func gather(to target: DisplayRecord, displays: [DisplayRecord], pids: [pid_t],
                       sourceIDs: Set<String>? = nil, strict: Bool = false) async throws -> MigrationReport {
        guard AXIsProcessTrusted() else { throw ScreenOperationError.permissionRequired }
        var report = MigrationReport()
        lastMigrated = []
        lastMigratedLocal = []
        let selfPID = getpid()
        for pid in pids {
            if pid == selfPID {
                let outcome = await Self.gatherLocal(to: target, displays: displays, sourceIDs: sourceIDs,
                                                     strict: strict, saved: savedLocal)
                savedLocal = outcome.saved
                lastMigratedLocal.append(contentsOf: outcome.migratedWindowNumbers)
                report.moved += outcome.report.moved
                report.failed += outcome.report.failed
                report.skipped += outcome.report.skipped
                report.blocked += outcome.report.blocked
                continue
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.4)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
                report.unreadableApplications += 1
                continue
            }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.4)
                // Finder exposes its desktop scroll area through AXWindows; it is not an application window.
                guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
                guard let original = frame(window), original.width > 1, original.height > 1 else {
                    report.skipped += 1; continue
                }
                // Ignore hidden helper windows parked far outside every physical desktop.
                guard let source = WindowPlacement.owningDisplay(for: original, displays: displays) else { continue }
                if source.id == target.id { continue }
                if let sourceIDs, !sourceIDs.contains(source.id) { continue }
                guard !bool(window, kAXMinimizedAttribute), !bool(window, "AXFullScreen"),
                      settable(window, kAXPositionAttribute) else {
                    report.skipped += 1
                    if strict { report.blocked += 1 }
                    continue
                }
                let canResize = settable(window, kAXSizeAttribute)
                let desired = WindowPlacement.movedFrame(original, from: source.visibleFrame,
                                                         to: target.visibleFrame, canResize: canResize)
                if !saved.contains(where: { CFEqual($0.element, window) }) {
                    saved.append(SavedWindow(element: window, frame: original, displayIdentity: source.id))
                }
                if setFrame(window, desired, canResize: canResize),
                   let actual = frame(window),
                   WindowPlacement.isPlaced(actual, desired: desired, within: target.visibleFrame, targetID: target.id, displays: displays) {
                    report.moved += 1
                    lastMigrated.append(window)
                } else { report.failed += 1 }
            }
        }
        logger.info("Window migration finished: moved=\(report.moved), failed=\(report.failed), skipped=\(report.skipped)")
        return report
    }

    /// Correct only windows from the most recent migration after the desktop coordinate origin changes.
    public func settleMigration(to target: DisplayRecord) async -> MigrationReport {
        var report = MigrationReport()
        if !lastMigratedLocal.isEmpty {
            let local = await Self.settleLocalMigration(windowNumbers: lastMigratedLocal, to: target)
            report.moved += local.moved
            report.failed += local.failed
        }
        for window in lastMigrated {
            guard let actual = frame(window) else { continue }
            if target.visibleFrame.contains(actual) { continue }
            let canResize = settable(window, kAXSizeAttribute)
            let desired = WindowPlacement.movedFrame(actual, from: target.visibleFrame,
                                                     to: target.visibleFrame, canResize: canResize)
            if setFrame(window, desired, canResize: canResize),
               let settled = frame(window),
               WindowPlacement.isPlaced(settled, desired: desired, within: target.visibleFrame) {
                report.moved += 1
            } else { report.failed += 1 }
        }
        return report
    }

    public func verifyVacated(sourceIDs: Set<String>, displays: [DisplayRecord], pids: [pid_t]) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let selfPID = getpid()
        for pid in pids {
            if pid == selfPID {
                guard await Self.verifyLocalVacated(sourceIDs: sourceIDs, displays: displays) else { return false }
                continue
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.4)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return false }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.4)
                guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
                guard let rect = frame(window), rect.width > 1, rect.height > 1 else { continue }
                if let source = WindowPlacement.owningDisplay(for: rect, displays: displays), sourceIDs.contains(source.id) {
                    return false
                }
            }
        }
        return true
    }

    public func restore(displays: [DisplayRecord]) async -> MigrationReport {
        var report = MigrationReport()
        if !savedLocal.isEmpty {
            let local = await Self.restoreLocal(saved: savedLocal, displays: displays)
            savedLocal = local.remaining
            report.moved += local.report.moved
            report.failed += local.report.failed
        }
        var remaining: [SavedWindow] = []
        for window in saved {
            guard window.displayIdentity.map({ id in displays.contains { $0.id == id && $0.isActive } }) ?? true else {
                remaining.append(window); report.failed += 1; continue
            }
            let targetBounds = window.displayIdentity.flatMap { id in displays.first { $0.id == id }?.visibleFrame } ?? window.frame
            if setFrame(window.element, window.frame, canResize: settable(window.element, kAXSizeAttribute)),
               let actual = frame(window.element),
               WindowPlacement.isPlaced(actual, desired: window.frame, within: targetBounds) {
                report.moved += 1
            } else {
                // Closed windows no longer need recovery; keep live windows for a later retry.
                if frame(window.element) != nil { remaining.append(window) }
                report.failed += 1
            }
        }
        saved = remaining
        logger.info("Window restoration finished: restored=\(report.moved), failed=\(report.failed)")
        return report
    }

    public func hasSavedWindows() -> Bool { !saved.isEmpty || !savedLocal.isEmpty }

    public func windowFrames(pid: pid_t) async -> [CGRect] {
        if pid == getpid() {
            return await Self.localWindowFrames()
        }
        let app = AXUIElementCreateApplication(pid)
        return (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).compactMap(frame)
    }

    @MainActor
    private static func managedLocalWindows() -> [NSWindow] {
        guard let app = NSApp else { return [] }
        return app.windows.filter { window in
            (window.isVisible || window.isMiniaturized)
                && !window.isSheet
                && window.sheetParent == nil
                && !(window is NSPanel)
                && window.level == .normal
                && (window.styleMask.contains(.titled) || window.styleMask.contains(.fullScreen))
        }
    }

    @MainActor
    private static func mainDisplayHeight(from displays: [DisplayRecord]? = nil) -> CGFloat {
        displays?.first(where: \.isMain)?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    }

    @MainActor
    private static func localInventory(pid: pid_t, displays: [DisplayRecord]) -> [WindowPreview] {
        let mainHeight = mainDisplayHeight(from: displays)
        var previews: [WindowPreview] = []
        for window in managedLocalWindows() {
            let rect = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            guard rect.width > 1, rect.height > 1,
                  let display = WindowPlacement.owningDisplay(for: rect, displays: displays) else { continue }
            let restriction: WindowRestriction?
            if window.isMiniaturized { restriction = .minimized }
            else if window.styleMask.contains(.fullScreen) { restriction = .fullScreen }
            else if !window.isMovable { restriction = .fixed }
            else { restriction = nil }
            previews.append(WindowPreview(applicationPID: pid, displayID: display.id, restriction: restriction))
        }
        return previews
    }

    @MainActor
    private static func gatherLocal(to target: DisplayRecord, displays: [DisplayRecord], sourceIDs: Set<String>?,
                                    strict: Bool, saved: [SavedLocalWindow]) -> LocalGatherOutcome {
        var outcome = LocalGatherOutcome(saved: saved)
        let mainHeight = mainDisplayHeight(from: displays)
        for window in managedLocalWindows() {
            let original = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            guard original.width > 1, original.height > 1 else {
                outcome.report.skipped += 1; continue
            }
            guard let source = WindowPlacement.owningDisplay(for: original, displays: displays) else { continue }
            if source.id == target.id { continue }
            if let sourceIDs, !sourceIDs.contains(source.id) { continue }
            guard !window.isMiniaturized, !window.styleMask.contains(.fullScreen), window.isMovable else {
                outcome.report.skipped += 1
                if strict { outcome.report.blocked += 1 }
                continue
            }
            let canResize = window.styleMask.contains(.resizable)
            let desired = WindowPlacement.movedFrame(original, from: source.visibleFrame,
                                                     to: target.visibleFrame, canResize: canResize)
            let number = window.windowNumber
            if !outcome.saved.contains(where: { $0.windowNumber == number }) {
                outcome.saved.append(SavedLocalWindow(windowNumber: number, frame: original, displayIdentity: source.id))
            }
            let appKitDesired = WindowPlacement.quartzToAppKit(desired, mainDisplayHeight: mainHeight)
            window.setFrame(appKitDesired, display: true, animate: false)
            CATransaction.flush()
            let actual = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            if WindowPlacement.isPlaced(actual, desired: desired, within: target.visibleFrame, targetID: target.id, displays: displays) {
                outcome.report.moved += 1
                outcome.migratedWindowNumbers.append(number)
            } else { outcome.report.failed += 1 }
        }
        return outcome
    }

    @MainActor
    private static func settleLocalMigration(windowNumbers: [Int], to target: DisplayRecord) -> MigrationReport {
        var report = MigrationReport()
        let mainHeight = mainDisplayHeight()
        let windowsByNumber = Dictionary(uniqueKeysWithValues: managedLocalWindows().map { ($0.windowNumber, $0) })
        for number in windowNumbers {
            guard let window = windowsByNumber[number] else { continue }
            let actual = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            if target.visibleFrame.contains(actual) { continue }
            let canResize = window.styleMask.contains(.resizable)
            let desired = WindowPlacement.movedFrame(actual, from: target.visibleFrame,
                                                     to: target.visibleFrame, canResize: canResize)
            let appKitDesired = WindowPlacement.quartzToAppKit(desired, mainDisplayHeight: mainHeight)
            window.setFrame(appKitDesired, display: true, animate: false)
            CATransaction.flush()
            let settled = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            if WindowPlacement.isPlaced(settled, desired: desired, within: target.visibleFrame) {
                report.moved += 1
            } else { report.failed += 1 }
        }
        return report
    }

    @MainActor
    private static func verifyLocalVacated(sourceIDs: Set<String>, displays: [DisplayRecord]) -> Bool {
        let mainHeight = mainDisplayHeight(from: displays)
        for window in managedLocalWindows() {
            let rect = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            guard rect.width > 1, rect.height > 1 else { continue }
            if let source = WindowPlacement.owningDisplay(for: rect, displays: displays), sourceIDs.contains(source.id) {
                return false
            }
        }
        return true
    }

    @MainActor
    private static func restoreLocal(saved: [SavedLocalWindow], displays: [DisplayRecord]) -> LocalRestoreOutcome {
        var outcome = LocalRestoreOutcome()
        let mainHeight = mainDisplayHeight(from: displays)
        let windowsByNumber = Dictionary(uniqueKeysWithValues: managedLocalWindows().map { ($0.windowNumber, $0) })
        for item in saved {
            guard item.displayIdentity.map({ id in displays.contains { $0.id == id && $0.isActive } }) ?? true else {
                outcome.remaining.append(item); outcome.report.failed += 1; continue
            }
            guard let window = windowsByNumber[item.windowNumber] else { continue }
            let targetBounds = item.displayIdentity.flatMap { id in displays.first { $0.id == id }?.visibleFrame } ?? item.frame
            let appKitFrame = WindowPlacement.quartzToAppKit(item.frame, mainDisplayHeight: mainHeight)
            window.setFrame(appKitFrame, display: true, animate: false)
            CATransaction.flush()
            let actual = WindowPlacement.appKitToQuartz(window.frame, mainDisplayHeight: mainHeight)
            if WindowPlacement.isPlaced(actual, desired: item.frame, within: targetBounds) {
                outcome.report.moved += 1
            } else {
                outcome.remaining.append(item)
                outcome.report.failed += 1
            }
        }
        return outcome
    }

    @MainActor
    private static func localWindowFrames() -> [CGRect] {
        let mainHeight = mainDisplayHeight()
        return managedLocalWindows().map { WindowPlacement.appKitToQuartz($0.frame, mainDisplayHeight: mainHeight) }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func bool(_ element: AXUIElement, _ name: String) -> Bool {
        attribute(element, name) as? Bool ?? false
    }

    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func settable(_ window: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, name as CFString, &result) == .success && result.boolValue
    }

    private func setFrame(_ window: AXUIElement, _ rect: CGRect, canResize: Bool) -> Bool {
        var point = rect.origin
        guard let position = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success else { return false }
        if canResize {
            var size = rect.size
            guard let dimensions = AXValueCreate(.cgSize, &size),
                  AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success else { return false }
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        return true
    }
}
