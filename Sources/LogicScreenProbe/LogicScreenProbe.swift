import AppKit
import ApplicationServices
import LogicScreenCore
import LogicScreenPlatform

@main
struct LogicScreenProbe {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let service = DisplayService()
        let screens = service.displays()
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            switch arguments.first ?? "--diagnose" {
            case "--diagnose":
                struct Diagnostics: Encodable {
                    let system: String
                    let accessibilityTrusted: Bool
                    let disconnectionSymbolAvailable: Bool
                    let displays: [DisplayRecord]
                }
                let report = Diagnostics(system: ProcessInfo.processInfo.operatingSystemVersionString,
                                         accessibilityTrusted: AXIsProcessTrusted(),
                                         disconnectionSymbolAvailable: service.supportsDisconnection, displays: screens)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            case "--exercise-windows":
                guard arguments.count == 2, let pid = Int32(arguments[1]), pid != getpid(),
                      NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "dev.logicscreen.app" else {
                    throw ScreenOperationError.unavailable("仅允许测试独立启动的 LogicScreen 验证窗口。")
                }
                let windows = WindowService()
                let before = await windows.windowFrames(pid: pid)
                guard let first = before.first,
                      let origin = WindowPlacement.owningDisplay(for: first, displays: screens),
                      let target = screens.first(where: { $0.isActive && $0.id != origin.id }) else {
                    throw ScreenOperationError.unavailable("需要一个 LogicScreen 验证窗口和两块屏幕。")
                }
                let moved = try await windows.gather(to: target, displays: screens, pids: [pid])
                try await Task.sleep(for: .milliseconds(400))
                let after = await windows.windowFrames(pid: pid)
                let restored = await windows.restore(displays: screens)
                try await Task.sleep(for: .milliseconds(400))
                let final = await windows.windowFrames(pid: pid)
                let restoredAll = before.allSatisfy { expected in final.contains { approx($0, expected) } }
                guard moved.moved > 0, moved.failed == 0,
                      after.contains(where: { $0.intersects(target.visibleFrame) }),
                      restored.failed == 0, restoredAll else {
                    throw ScreenOperationError.verificationFailed("窗口迁移或原位置恢复未通过验证。")
                }
                print("PASS: moved \(moved.moved) fixture windows to the other display; restored original geometry.")
            case "--exercise-main":
                guard let target = screens.first(where: { $0.isActive && !$0.isMain }) else {
                    throw ScreenOperationError.unavailable("需要两块活动屏幕。")
                }
                do {
                    try service.setMain(target.id)
                    try await Task.sleep(for: .milliseconds(800))
                    let succeeded = service.displays().contains { $0.id == target.id && $0.isMain }
                    try service.restore(screens)
                    try await Task.sleep(for: .milliseconds(800))
                    guard succeeded, screens.filter(\.isActive).allSatisfy({ saved in
                        service.displays().contains { $0.id == saved.id && $0.isMain == saved.isMain && approx($0.frame, saved.frame) }
                    }) else { throw ScreenOperationError.verificationFailed("主屏切换或布局恢复未通过验证。") }
                    print("PASS: main display switched; original main display and layout restored.")
                } catch { try? service.restore(screens); throw error }
            case "--exercise-display":
                // This command is deliberately separate from normal diagnostics and requires an explicit ID.
                guard arguments.count == 2, let id = UInt32(arguments[1]),
                      let target = screens.first(where: { $0.displayID == id && $0.isActive && !$0.isMain }),
                      screens.filter(\.isActive).count > 1 else {
                    throw ScreenOperationError.unavailable("只能指定一块非主屏进行断开恢复验证。")
                }
                let windows = WindowService()
                let pids = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
                    .map(\.processIdentifier)
                guard let retained = screens.first(where: \.isMain) else { throw ScreenOperationError.lastDisplay }
                do {
                    _ = try await ScreenShutdownSequence.perform(migrate: {
                        try await windows.gather(to: retained, displays: screens, pids: pids, sourceIDs: [target.id], strict: true)
                    }, verify: {
                        await windows.verifyVacated(sourceIDs: [target.id], displays: service.displays(), pids: pids)
                    }, disconnect: {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { _exit(124) }
                        try service.disconnect([target.id])
                    })
                    try await Task.sleep(for: .seconds(2))
                    let inactive = !service.displays().contains { $0.id == target.id && $0.isActive }
                    try service.restore(screens)
                    try await Task.sleep(for: .seconds(1))
                    try service.restoreOrigins(screens)
                    try await Task.sleep(for: .milliseconds(400))
                    let restoration = await windows.restore(displays: service.displays())
                    guard inactive, service.displays().contains(where: { $0.id == target.id && $0.isActive }) else {
                        throw ScreenOperationError.verificationFailed("屏幕断开或软件重新连接未通过验证。")
                    }
                    print("PASS: source windows migrated and verified before disconnection; secondary display reconnected; window restore failures=\(restoration.failed).")
                } catch {
                    try? service.restore(screens)
                    try? await Task.sleep(for: .milliseconds(800))
                    _ = await windows.restore(displays: service.displays())
                    throw error
                }
            default:
                throw ScreenOperationError.unavailable("支持 --diagnose、--exercise-windows PID、--exercise-main、--exercise-display ID。")
            }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func approx(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12
            && abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }
}
