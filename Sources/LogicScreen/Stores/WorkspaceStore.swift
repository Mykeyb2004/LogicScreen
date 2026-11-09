import AppKit
import ApplicationServices
import LogicScreenCore
import LogicScreenPlatform
import Observation
import OSLog

@MainActor @Observable
final class WorkspaceStore {
    private(set) var displays: [DisplayRecord] = []
    var selectedID: String?
    private(set) var isTrusted = false
    private(set) var isBusy = false
    private(set) var canRestore = false
    private(set) var remainingSeconds: Int?
    private(set) var status = "选择一块屏幕，收拢窗口或切换工作布局。"
    private(set) var statusIsError = false
    var errorMessage: String?

    @ObservationIgnored private let displayService = DisplayService()
    @ObservationIgnored private let windowService = WindowService()
    @ObservationIgnored private let labels = ScreenLabels()
    @ObservationIgnored private let shortcut = RecoveryShortcut()
    @ObservationIgnored private var snapshot: [DisplayRecord]?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var focusedDisplayID: String?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.logicscreen.app", category: "Workspace")

    var selected: DisplayRecord? { displays.first { $0.id == selectedID } }
    var activeCount: Int { displays.filter(\.isActive).count }
    var supportsDisconnection: Bool { displayService.supportsDisconnection }

    func start() {
        guard polling == nil else { return }
        refresh()
        shortcut.register { [weak self] in Task { await self?.restore() } }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.screenConfigurationChanged() } }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        logger.info("Workspace started")
    }

    func refresh() {
        displays = displayService.displays()
        isTrusted = AXIsProcessTrusted()
        if selectedID == nil || !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first(where: \.isActive)?.id
        }
    }

    func showLabels() { labels.show() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func gather() async {
        guard let target = selected, target.isActive, !isBusy, remainingSeconds == nil else { return }
        await perform {
            let report = try await self.windowService.gather(to: target, displays: self.displays, pids: self.applicationPIDs)
            self.status = report.message
            self.canRestore = await self.windowService.hasSavedWindows() || self.snapshot != nil
        }
    }

    func makeMain() async {
        guard let target = selected, target.isActive, !isBusy, remainingSeconds == nil else { return }
        await perform {
            self.saveLayoutIfNeeded()
            try self.displayService.setMain(target.id)
            try await Task.sleep(for: .milliseconds(650))
            self.refresh()
            guard self.selected?.isMain == true else {
                throw ScreenOperationError.verificationFailed("系统未完成主屏切换，原布局仍可恢复。")
            }
            self.status = "已将 \(target.name) 设为主屏。退出应用后恢复原布局。"
        }
    }

    func focus(only disconnectID: String? = nil) async {
        guard let target = selected, target.isActive, !isBusy, remainingSeconds == nil else { return }
        await perform {
            self.refresh()
            let ids = disconnectID.map { Set([$0]) } ?? Set(self.displays.filter { $0.isActive && $0.id != target.id }.map(\.id))
            guard !ids.isEmpty else { return }
            try DisplaySafety.validateDisconnection(ids: ids, displays: self.displays)
            guard self.isTrusted else { throw ScreenOperationError.permissionRequired }
            self.saveLayoutIfNeeded()
            let report = try await ScreenShutdownSequence.perform(migrate: {
                self.status = "正在将待停用屏幕的窗口移到 \(target.name)…"
                return try await self.windowService.gather(to: target, displays: self.displays,
                                                           pids: self.applicationPIDs, sourceIDs: ids, strict: true)
            }, verify: {
                self.status = "正在核验窗口已迁移，屏幕仍保持开启…"
                self.refresh()
                guard self.displays.contains(where: { $0.id == target.id && $0.isActive }) else { return false }
                return await self.windowService.verifyVacated(sourceIDs: ids, displays: self.displays, pids: self.applicationPIDs)
            }, disconnect: {
                self.status = "窗口迁移已确认，正在停用屏幕…"
                try self.displayService.disconnect(ids)
            })
            self.focusedDisplayID = target.id
            try await Task.sleep(for: .milliseconds(800))
            self.refresh()
            guard self.displays.contains(where: { $0.id == target.id && $0.isActive }),
                  !self.displays.contains(where: { ids.contains($0.id) && $0.isActive }) else {
                try? self.displayService.restore(self.snapshot ?? [])
                throw ScreenOperationError.verificationFailed("屏幕停用未通过检查，已请求恢复原布局。")
            }
            // Reflow can change the main origin. Take fresh screen geometry before correcting windows.
            if let freshTarget = self.displays.first(where: { $0.id == target.id }) {
                _ = try await self.windowService.gather(to: freshTarget, displays: self.displays, pids: self.applicationPIDs)
            }
            self.status = report.message + "请确认屏幕可用。"
            self.beginCountdown()
        }
    }

    func reconnectSelected() async {
        guard let target = selected, !target.isActive, !isBusy else { return }
        await perform {
            try self.displayService.reconnect(target)
            try await Task.sleep(for: .milliseconds(800))
            self.refresh()
            guard self.selected?.isActive == true else {
                throw ScreenOperationError.verificationFailed("未能重新连接。请使用“恢复布局”；必要时拔插显示器连接线。")
            }
            self.status = "已重新连接 \(target.name)。"
        }
    }

    func keepConfiguration() {
        countdown?.cancel()
        remainingSeconds = nil
        status = "已保留当前配置，可随时恢复。退出应用后屏幕布局自动还原。"
    }

    func restore() async {
        guard !isBusy, canRestore else { return }
        countdown?.cancel()
        countdown = nil
        remainingSeconds = nil
        focusedDisplayID = nil
        await perform {
            if let snapshot = self.snapshot {
                try self.displayService.restore(snapshot)
                try await Task.sleep(for: .milliseconds(800))
                self.refresh()
                try self.displayService.restoreOrigins(snapshot)
                try await Task.sleep(for: .milliseconds(400))
                self.refresh()
                let missing = snapshot.filter(\.isActive).filter { saved in
                    !self.displays.contains { $0.id == saved.id && $0.isActive }
                }
                guard missing.isEmpty else {
                    throw ScreenOperationError.verificationFailed("仍有屏幕无法连接。退出应用可让系统撤销配置；必要时拔插显示器连接线。")
                }
                self.snapshot = nil
            }
            let report = await self.windowService.restore(displays: self.displays)
            self.canRestore = await self.windowService.hasSavedWindows()
            self.status = report.failed == 0 ? "已恢复屏幕布局和已记录的窗口位置。" : "屏幕布局已恢复，\(report.failed) 个窗口未能还原，可再次尝试。"
        }
    }

    private var applicationPIDs: [pid_t] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map(\.processIdentifier)
    }

    private func saveLayoutIfNeeded() {
        if snapshot == nil { snapshot = displays.filter(\.isActive) }
        canRestore = true
    }

    private func perform(_ action: () async throws -> Void) async {
        isBusy = true
        statusIsError = false
        status = "正在调整，请稍候…"
        defer { isBusy = false; refresh() }
        do { try await action() }
        catch {
            status = error.localizedDescription
            statusIsError = true
            errorMessage = status
            logger.error("Workspace action failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func beginCountdown() {
        countdown?.cancel()
        remainingSeconds = 15
        countdown = Task { [weak self] in
            for remaining in stride(from: 14, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.remainingSeconds = remaining
            }
            await self?.restore()
        }
    }

    private func screenConfigurationChanged() {
        refresh()
        guard !isBusy, let focusedDisplayID,
              !displays.contains(where: { $0.id == focusedDisplayID && $0.isActive }) else { return }
        Task { await restore() }
    }
}
