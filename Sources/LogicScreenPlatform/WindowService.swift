import ApplicationServices
import Foundation
import LogicScreenCore
import OSLog

/// Accessibility IPC runs on this actor rather than blocking the UI thread.
public actor WindowService {
    private struct SavedWindow {
        let element: AXUIElement
        let frame: CGRect
        let displayIdentity: String?
    }
    private var saved: [SavedWindow] = []
    private let logger = Logger(subsystem: "dev.logicscreen.app", category: "Windows")

    public init() {}

    public func gather(to target: DisplayRecord, displays: [DisplayRecord], pids: [pid_t],
                       sourceIDs: Set<String>? = nil, strict: Bool = false) throws -> MigrationReport {
        guard AXIsProcessTrusted() else { throw ScreenOperationError.permissionRequired }
        var report = MigrationReport()
        for pid in pids {
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
                   let actual = frame(window), actual.intersects(target.visibleFrame),
                   abs(actual.minX - desired.minX) < 12, abs(actual.minY - desired.minY) < 12 {
                    report.moved += 1
                } else { report.failed += 1 }
            }
        }
        logger.info("Window migration finished: moved=\(report.moved), failed=\(report.failed), skipped=\(report.skipped)")
        return report
    }

    public func verifyVacated(sourceIDs: Set<String>, displays: [DisplayRecord], pids: [pid_t]) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        for pid in pids {
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

    public func restore(displays: [DisplayRecord]) -> MigrationReport {
        var report = MigrationReport()
        var remaining: [SavedWindow] = []
        for window in saved {
            guard window.displayIdentity.map({ id in displays.contains { $0.id == id && $0.isActive } }) ?? true else {
                remaining.append(window); report.failed += 1; continue
            }
            if setFrame(window.element, window.frame, canResize: settable(window.element, kAXSizeAttribute)),
               let actual = frame(window.element), abs(actual.minX - window.frame.minX) < 12,
               abs(actual.minY - window.frame.minY) < 12 {
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

    public func hasSavedWindows() -> Bool { !saved.isEmpty }

    public func windowFrames(pid: pid_t) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        return (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).compactMap(frame)
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
        if canResize {
            var size = rect.size
            guard let value = AXValueCreate(.cgSize, &size),
                  AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success else { return false }
        }
        var point = rect.origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }
}
