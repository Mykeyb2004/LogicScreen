import Foundation

public struct MigrationReport: Sendable {
    public var moved = 0
    public var failed = 0
    public var skipped = 0
    public var blocked = 0
    public var unreadableApplications = 0

    public init(moved: Int = 0, failed: Int = 0, skipped: Int = 0, blocked: Int = 0, unreadableApplications: Int = 0) {
        self.moved = moved
        self.failed = failed
        self.skipped = skipped
        self.blocked = blocked
        self.unreadableApplications = unreadableApplications
    }

    public var message: String {
        var parts = ["已移动 \(moved) 个窗口"]
        if skipped > 0 { parts.append("跳过 \(skipped) 个特殊窗口") }
        if failed > 0 { parts.append("\(failed) 个窗口未能移动") }
        if blocked > 0 { parts.append("待停用屏幕上仍有 \(blocked) 个特殊窗口，请先退出全屏或还原窗口") }
        if unreadableApplications > 0 { parts.append("\(unreadableApplications) 个应用无法读取") }
        return parts.joined(separator: "，") + "。"
    }
}

/// Disconnection is unreachable until both migration and a fresh window inventory succeed.
public enum ScreenShutdownSequence {
    public static func perform(migrate: () async throws -> MigrationReport,
                               verify: () async throws -> Bool,
                               disconnect: () async throws -> Void) async throws -> MigrationReport {
        let report = try await migrate()
        guard report.failed == 0, report.blocked == 0, report.unreadableApplications == 0 else {
            throw ScreenOperationError.verificationFailed(report.message + "屏幕保持开启。")
        }
        guard try await verify() else {
            throw ScreenOperationError.verificationFailed("待停用屏幕上仍有窗口，或窗口状态发生变化。屏幕保持开启，请重试。")
        }
        try await disconnect()
        return report
    }
}
