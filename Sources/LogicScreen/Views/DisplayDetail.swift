import SwiftUI
import LogicScreenCore

struct DisplayDetail: View {
    @Bindable var store: WorkspaceStore
    let screen: DisplayRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(screen.name).font(.system(size: 28, weight: .semibold)).textSelection(.enabled)
                    Text(screen.isActive ? "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) 逻辑点 · \(screen.isBuiltIn ? "内建显示器" : "外接显示器")" : "当前未参与桌面布局")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Label(screen.isActive ? (screen.isMain ? "主屏幕" : "已连接") : "已停用", systemImage: screen.isActive ? "circle.fill" : "power")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(screen.isActive ? Color.green : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                    if screen.isActive && !screen.isMain {
                        Button("设为主屏幕") { Task { await store.makeMain() } }
                            .controlSize(.small).disabled(store.controlsLocked || screen.isMirrored)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("你的屏幕布局").font(.headline)
                    Spacer()
                    Text("点击屏幕选择目标").font(.caption).foregroundStyle(.secondary)
                }
                ScreenMap(displays: store.displays, selectedID: $store.selectedID, inventory: store.inventory)
                    .frame(height: 210)
            }
            if let phase = store.phase { OperationProgress(phase: phase) }
            if screen.isActive {
                actionCard
                WindowPreviewList(store: store, target: screen)
            } else { reconnectCard }
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.on.rectangle").font(.title2).foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text("把工作聚到这块屏幕").font(.headline)
                    Text("将其他屏幕的窗口移过来，尽量保留大小和相对位置。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("收拢窗口", systemImage: "rectangle.on.rectangle") { Task { await store.gather() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.isTrusted || store.controlsLocked || store.activeCount < 2)
                    .help("收拢到 \(screen.name)（⇧⌘G）")
                Button("仅使用此屏幕…", systemImage: "display") {
                    let ids = Set(store.activeDisplays.filter { $0.id != screen.id }.map(\.id))
                    Task { await store.prepareFocus(targetID: screen.id, sourceIDs: ids) }
                }
                .disabled(!store.canDisconnect)
                Spacer(minLength: 0)
                Menu {
                    Button("设为主屏幕") { Task { await store.makeMain() } }
                        .disabled(screen.isMain || store.controlsLocked || screen.isMirrored)
                    Menu("停用此屏幕，窗口移到") {
                        ForEach(store.activeDisplays.filter { $0.id != screen.id }) { target in
                            Button(String(target.name.prefix(24))) {
                                Task { await store.prepareFocus(targetID: target.id, sourceIDs: [screen.id]) }
                            }
                        }
                    }
                    .disabled(!store.canDisconnect)
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).fixedSize().help("更多屏幕操作")
                .accessibilityLabel("更多屏幕操作")
            }
            Text(disconnectionHint).font(.caption).foregroundStyle(.secondary)
        }
        .workspaceCard()
    }

    private var disconnectionHint: String {
        if store.activeCount < 2 { return "连接另一块屏幕后，即可跨屏收拢窗口。" }
        if !store.supportsDisconnection { return "当前系统支持窗口迁移，暂不支持屏幕停用。" }
        if store.activeDisplays.contains(where: \.isMirrored) { return "当前处于镜像模式，请先在系统设置中改为扩展显示。" }
        return "仅使用此屏幕：先迁移 → 核验 → 停用其他屏幕。停用功能为实验功能。"
    }

    private var reconnectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("让这块屏幕重新加入工作空间", systemImage: "power").font(.headline)
            Text("显示器需保持连接。重新连接后，可使用“恢复布局”还原本次记录的窗口位置。")
                .foregroundStyle(.secondary)
            Button("重新连接屏幕", systemImage: "power") { Task { await store.reconnectSelected() } }
                .buttonStyle(.borderedProminent).disabled(store.controlsLocked || !store.supportsDisconnection)
        }
        .frame(maxWidth: .infinity, alignment: .leading).workspaceCard()
    }
}

extension View {
    func workspaceCard() -> some View {
        padding(18)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1) }
    }
}
