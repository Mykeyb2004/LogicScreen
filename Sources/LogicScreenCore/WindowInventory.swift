import Foundation

public enum WindowRestriction: String, Sendable {
    case minimized, fullScreen, fixed

    public var label: String {
        switch self {
        case .minimized: return "最小化"
        case .fullScreen: return "全屏"
        case .fixed: return "不可移动"
        }
    }
}

/// A title-free inventory for previews. A fresh migration and verification remain mandatory.
public struct WindowPreview: Sendable {
    public let applicationPID: Int32
    public let displayID: String
    public let restriction: WindowRestriction?

    public init(applicationPID: Int32, displayID: String, restriction: WindowRestriction? = nil) {
        self.applicationPID = applicationPID
        self.displayID = displayID
        self.restriction = restriction
    }
}

public struct WindowInventory: Sendable {
    public var windows: [WindowPreview]
    public var unreadablePIDs: [Int32]

    public init(windows: [WindowPreview] = [], unreadablePIDs: [Int32] = []) {
        self.windows = windows
        self.unreadablePIDs = unreadablePIDs
    }

    public func readiness(sourceIDs: Set<String>) -> MigrationReadiness {
        let sources = windows.filter { sourceIDs.contains($0.displayID) }
        return MigrationReadiness(movable: sources.filter { $0.restriction == nil }.count,
                                  blocked: sources.filter { $0.restriction != nil }.count,
                                  unreadableApplications: unreadablePIDs.count)
    }
}

public struct MigrationReadiness: Equatable, Sendable {
    public let movable: Int
    public let blocked: Int
    public let unreadableApplications: Int
    public var canProceed: Bool { blocked == 0 && unreadableApplications == 0 }
}
