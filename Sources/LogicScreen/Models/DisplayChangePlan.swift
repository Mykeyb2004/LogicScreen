import Foundation
import LogicScreenCore

struct DisplayChangePlan: Identifiable {
    let id = UUID()
    let target: DisplayRecord
    let sources: [DisplayRecord]
    let inventory: WindowInventory

    var sourceIDs: Set<String> { Set(sources.map(\.id)) }
    var readiness: MigrationReadiness { inventory.readiness(sourceIDs: sourceIDs) }
}

enum WorkspacePhase: Int, CaseIterable {
    case moving, verifying, switching, settling

    var title: String {
        switch self {
        case .moving: return "迁移窗口"
        case .verifying: return "核验迁移"
        case .switching: return "停用屏幕"
        case .settling: return "确认布局"
        }
    }
}
