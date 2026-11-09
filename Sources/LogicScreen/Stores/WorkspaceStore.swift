import AppKit
import ApplicationServices
import LogicScreenCore
import LogicScreenPlatform
import Observation
import OSLog

@MainActor @Observable
final class WorkspaceStore {
    var displays: [DisplayRecord] = []
    var selectedID: String?
    var isTrusted = false
    var isBusy = false
    var canRestore = false
    var remainingSeconds: Int?
    var countdownDuration = 15
    var status = "选择目标屏幕，让窗口回到同一个工作空间。"
    var statusIsError = false
    var phase: WorkspacePhase?
    var inventory: WindowInventory?
    var isLoadingWindows = false
    var inventoryError: String?
    var plan: DisplayChangePlan?
    var isPreparing = false

    @ObservationIgnored let displayService = DisplayService()
    @ObservationIgnored let windowService = WindowService()
    @ObservationIgnored private let labels = ScreenLabels()
    @ObservationIgnored private let shortcut = RecoveryShortcut()
    @ObservationIgnored var snapshot: [DisplayRecord]?
    @ObservationIgnored let countdown = ConfirmationTimer()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored var focusedDisplayID: String?
    @ObservationIgnored var restoreRequested = false
    @ObservationIgnored let logger = Logger(subsystem: "dev.logicscreen.app", category: "Workspace")

    var selected: DisplayRecord? { displays.first { $0.id == selectedID } }
    var activeDisplays: [DisplayRecord] { displays.filter(\.isActive) }
    var activeCount: Int { activeDisplays.count }
    var supportsDisconnection: Bool { displayService.supportsDisconnection }
    var controlsLocked: Bool { isBusy || isPreparing || remainingSeconds != nil || plan != nil }
    var canDisconnect: Bool {
        activeCount > 1 && isTrusted && !controlsLocked && supportsDisconnection && !activeDisplays.contains(where: \.isMirrored)
    }

    func start() {
        guard polling == nil else { return }
        refresh()
        shortcut.register { [weak self] in Task { await self?.restore() } }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.screenConfigurationChanged() } }
        polling = Task { [weak self] in
            var tick = 0
            await self?.reloadWindows()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                let wasTrusted = self.isTrusted
                self.refresh()
                tick += 1
                if wasTrusted != self.isTrusted || tick % 5 == 0 { await self.reloadWindows() }
            }
        }
        logger.info("Workspace started")
    }

    func refresh() {
        let current = displayService.displays()
        if displays != current { displays = current }
        isTrusted = AXIsProcessTrusted()
        if !isTrusted { inventory = nil }
        if selectedID == nil || !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first(where: \.isActive)?.id
        }
    }

    func reloadWindows() async {
        guard !isBusy, !isLoadingWindows else { return }
        refresh()
        guard isTrusted else { inventory = nil; return }
        isLoadingWindows = true
        let geometry = displays
        defer { isLoadingWindows = false }
        do {
            let result = try await windowService.inventory(displays: geometry, pids: applicationPIDs)
            // An old desktop snapshot must never replace a result for the new layout.
            guard geometry == displays, !isBusy else { return }
            inventory = result
            inventoryError = nil
        } catch { inventoryError = error.localizedDescription }
    }

    func prepareFocus(targetID: String, sourceIDs: Set<String>) async {
        guard activeCount > 1, isTrusted, !isBusy, !isPreparing, remainingSeconds == nil,
              supportsDisconnection, !activeDisplays.contains(where: \.isMirrored) else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            refresh()
            let geometry = displays
            guard let target = geometry.first(where: { $0.id == targetID && $0.isActive }),
                  !sourceIDs.isEmpty, !sourceIDs.contains(targetID) else { throw ScreenOperationError.missingDisplay }
            try DisplaySafety.validateDisconnection(ids: sourceIDs, displays: geometry)
            let preview = try await windowService.inventory(displays: geometry, pids: applicationPIDs)
            refresh()
            guard geometry == displays, !isBusy, remainingSeconds == nil else {
                throw ScreenOperationError.verificationFailed("屏幕布局发生了变化，请重新检查。")
            }
            inventory = preview
            plan = DisplayChangePlan(target: target, sources: geometry.filter { sourceIDs.contains($0.id) }, inventory: preview)
        } catch { showError(error) }
    }

    func windowCount(on id: String) -> Int? { inventory.map { $0.windows.filter { $0.displayID == id }.count } }
    func showLabels() { labels.show() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    var applicationPIDs: [pid_t] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map(\.processIdentifier)
    }

    func saveLayoutIfNeeded() {
        if snapshot == nil { snapshot = activeDisplays }
        canRestore = true
    }

    func perform(_ action: () async throws -> Void) async {
        isBusy = true
        statusIsError = false
        status = "正在调整工作空间…"
        do { try await action() }
        catch { showError(error) }
        let hasWindows = await windowService.hasSavedWindows()
        canRestore = hasWindows || snapshot != nil
        phase = nil
        isBusy = false
        refresh()
        if restoreRequested {
            restoreRequested = false
            await restore()
        } else { await reloadWindows() }
    }

    func showError(_ error: Error) {
        status = error.localizedDescription
        statusIsError = true
        logger.error("Workspace action failed: \(error.localizedDescription, privacy: .public)")
    }

    func beginCountdown() {
        countdown.cancel()
        let preference = UserDefaults.standard.integer(forKey: "confirmationDuration")
        countdownDuration = [15, 20, 30].contains(preference) ? preference : 15
        countdown.start(duration: TimeInterval(countdownDuration), tick: { [weak self] in
            self?.remainingSeconds = $0
        }, expired: { [weak self] in await self?.restore() })
    }

    private func screenConfigurationChanged() {
        refresh()
        guard !isBusy, let focusedDisplayID,
              !displays.contains(where: { $0.id == focusedDisplayID && $0.isActive }) else { return }
        Task { await restore() }
    }
}
