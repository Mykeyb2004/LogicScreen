import Foundation

public enum ScreenOperationError: LocalizedError {
    case unavailable(String)
    case missingDisplay
    case lastDisplay
    case mirroredDisplays
    case permissionRequired
    case systemFailure(String, Int32)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .missingDisplay: return "目标屏幕当前不可用，请刷新后重试。"
        case .lastDisplay: return "至少保留一块正在使用的屏幕。"
        case .mirroredDisplays: return "请先在系统设置中退出镜像模式，再操作屏幕布局。"
        case .permissionRequired: return "请先授予 LogicScreen 辅助功能权限。"
        case .systemFailure(let action, let code): return "\(action)失败（系统代码 \(code)）。"
        case .verificationFailed(let reason): return reason
        }
    }
}

public enum DisplaySafety {
    public static func validateDisconnection(ids: Set<String>, displays: [DisplayRecord]) throws {
        let active = displays.filter(\.isActive)
        guard ids.isSubset(of: Set(active.map(\.id))) else { throw ScreenOperationError.missingDisplay }
        guard active.contains(where: { !ids.contains($0.id) }) else { throw ScreenOperationError.lastDisplay }
        guard !active.contains(where: \.isMirrored) else { throw ScreenOperationError.mirroredDisplays }
    }
}
