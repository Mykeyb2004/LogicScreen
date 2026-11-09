import Foundation
import LogicScreenCore

extension WorkspaceStore {
    func gather() async {
        guard let target = selected, target.isActive, !controlsLocked else { return }
        await perform {
            self.status = "正在收拢窗口到 \(target.name)…"
            let report = try await self.windowService.gather(to: target, displays: self.displays, pids: self.applicationPIDs)
            self.status = report.message
            self.statusIsError = report.failed > 0 || report.unreadableApplications > 0
        }
    }

    func makeMain() async {
        guard let target = selected, target.isActive, !controlsLocked else { return }
        await perform {
            self.saveLayoutIfNeeded()
            try self.displayService.setMain(target.id)
            try await Task.sleep(for: .milliseconds(650))
            self.refresh()
            guard self.displays.contains(where: { $0.id == target.id && $0.isMain }) else {
                throw ScreenOperationError.verificationFailed("系统未完成主屏切换，可点击“恢复布局”还原。")
            }
            self.status = "已将 \(target.name) 设为主屏幕。"
        }
    }

    func focus(using plan: DisplayChangePlan) async {
        guard !isBusy, !isPreparing, remainingSeconds == nil else { return }
        self.plan = nil
        await perform {
            self.refresh()
            guard let target = self.displays.first(where: { $0.id == plan.target.id && $0.isActive }),
                  !plan.sourceIDs.contains(target.id) else { throw ScreenOperationError.missingDisplay }
            let ids = plan.sourceIDs
            try DisplaySafety.validateDisconnection(ids: ids, displays: self.displays)
            guard self.isTrusted else { throw ScreenOperationError.permissionRequired }
            self.saveLayoutIfNeeded()
            var attemptedSwitch = false
            do {
                let report = try await ScreenShutdownSequence.perform(migrate: {
                    self.phase = .moving
                    self.status = "正在将窗口移到 \(target.name)，所有屏幕仍保持开启…"
                    return try await self.windowService.gather(to: target, displays: self.displays,
                                                               pids: self.applicationPIDs, sourceIDs: ids, strict: true)
                }, verify: {
                    self.phase = .verifying
                    self.status = "正在重新检查待停用屏幕，确认窗口已迁移…"
                    self.refresh()
                    guard self.displays.contains(where: { $0.id == target.id && $0.isActive }) else { return false }
                    return await self.windowService.verifyVacated(sourceIDs: ids, displays: self.displays, pids: self.applicationPIDs)
                }, disconnect: {
                    self.phase = .switching
                    self.status = "窗口迁移已确认，正在停用屏幕…"
                    attemptedSwitch = true
                    try self.displayService.disconnect(ids)
                    self.focusedDisplayID = target.id
                    // Start protection before any fallible post-switch work.
                    self.beginCountdown()
                })
                self.phase = .settling
                try await Task.sleep(for: .milliseconds(800))
                self.refresh()
                guard let freshTarget = self.displays.first(where: { $0.id == target.id && $0.isActive }),
                      !self.displays.contains(where: { ids.contains($0.id) && $0.isActive }) else {
                    throw ScreenOperationError.verificationFailed("屏幕切换未通过检查。")
                }
                // Reflow can move the coordinate origin. Use the current geometry for correction.
                let correction = await self.windowService.settleMigration(to: freshTarget)
                guard correction.failed == 0 else {
                    throw ScreenOperationError.verificationFailed("切换后有窗口未能在目标屏幕上安顿。")
                }
                self.status = report.message + "请确认当前屏幕正常显示。"
            } catch {
                if attemptedSwitch {
                    self.countdown.cancel()
                    self.remainingSeconds = nil
                    self.focusedDisplayID = nil
                    let recovered: MigrationReport
                    do { recovered = try await self.restoreSavedWorkspace() }
                    catch let recoveryError {
                        throw ScreenOperationError.verificationFailed(error.localizedDescription + " 自动恢复未完成：" + recoveryError.localizedDescription)
                    }
                    throw ScreenOperationError.verificationFailed(error.localizedDescription +
                        (recovered.failed == 0 ? " 已恢复原工作空间。" : " 屏幕已恢复，部分窗口需要再次恢复。"))
                }
                throw error
            }
        }
    }

    func reconnectSelected() async {
        guard let target = selected, !target.isActive, !controlsLocked else { return }
        await perform {
            try self.displayService.reconnect(target)
            try await Task.sleep(for: .milliseconds(800))
            self.refresh()
            guard self.displays.contains(where: { $0.id == target.id && $0.isActive }) else {
                throw ScreenOperationError.verificationFailed("未能重新连接，请尝试“恢复布局”或重新插拔显示器。")
            }
            self.status = "已重新连接 \(target.name)。"
        }
    }

    func keepConfiguration() {
        guard !isBusy, remainingSeconds != nil else { return }
        countdown.cancel()
        remainingSeconds = nil
        status = "当前配置已保留。需要时可一键恢复，退出应用时也会还原。"
    }

    func restore() async {
        if isBusy { restoreRequested = true; return }
        guard canRestore else { return }
        plan = nil
        countdown.cancel()
        remainingSeconds = nil
        focusedDisplayID = nil
        await perform {
            self.status = "正在恢复屏幕连接、排列和窗口位置…"
            let report = try await self.restoreSavedWorkspace()
            self.statusIsError = report.failed > 0
            self.status = report.failed == 0 ? "已恢复原来的屏幕布局和窗口位置。" : "屏幕已恢复，\(report.failed) 个窗口未能还原，可再次尝试。"
        }
    }

    @discardableResult
    private func restoreSavedWorkspace() async throws -> MigrationReport {
        if let snapshot {
            try displayService.restore(snapshot)
            try await Task.sleep(for: .milliseconds(800))
            refresh()
            try displayService.restoreOrigins(snapshot)
            try await Task.sleep(for: .milliseconds(400))
            refresh()
            let missing = snapshot.filter(\.isActive).filter { saved in
                !displays.contains { $0.id == saved.id && $0.isActive }
            }
            guard missing.isEmpty else {
                throw ScreenOperationError.verificationFailed("仍有屏幕无法连接。请再次恢复；必要时重新插拔显示器。")
            }
            self.snapshot = nil
        }
        return await windowService.restore(displays: displays)
    }
}
