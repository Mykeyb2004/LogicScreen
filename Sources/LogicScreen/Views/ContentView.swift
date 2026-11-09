import LogicScreenCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @State private var confirmingDisconnection = false
    @State private var disconnectID: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                Section("屏幕") {
                    ForEach(store.displays) { display in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(display.name).lineLimit(1)
                                Text(display.isActive ? (display.isMain ? "主屏幕" : "扩展屏幕") : "已停用或未连接")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                .foregroundStyle(display.isActive ? Color.primary : Color.secondary)
                        }
                        .tag(display.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 270)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                if let screen = store.selected {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(screen.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                            Text(screen.isActive ? "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) 点 · \(screen.isMain ? "主屏幕" : "扩展屏幕")" : "已停用或未连接")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isBusy { ProgressView().controlSize(.small) }
                    }
                    ScreenMap(displays: store.displays, selectedID: $store.selectedID)
                        .frame(height: 185)
                    actions(for: screen)
                } else {
                    ContentUnavailableView("未发现屏幕", systemImage: "display.trianglebadge.exclamationmark",
                                           description: Text("请连接显示器，然后刷新屏幕列表。"))
                }
                if !store.isTrusted { permissionNotice }
                if let seconds = store.remainingSeconds { recoveryNotice(seconds: seconds) }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: store.statusIsError ? "exclamationmark.circle" : "info.circle")
                    Text(store.status).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout).foregroundStyle(store.statusIsError ? Color.orange : Color.secondary)
                Text("恢复快捷键 ⌃⌥⌘R · 退出应用后屏幕布局自动还原")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 530, minHeight: 540)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("识别屏幕", systemImage: "number.square") { store.showLabels() }
                    .help("在每块屏幕上显示名称与编号")
                Button("刷新", systemImage: "arrow.clockwise") { store.refresh() }
                Button("恢复布局", systemImage: "arrow.uturn.backward") { Task { await store.restore() } }
                    .disabled(!store.canRestore || store.isBusy)
            }
        }
        .confirmationDialog("停用其他屏幕", isPresented: $confirmingDisconnection, titleVisibility: .visible) {
            Button("迁移窗口并停用屏幕") { Task { await store.focus(only: disconnectID) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("先迁移窗口，核验成功后再停用屏幕。如果窗口无法迁移，屏幕保持开启。停用后有 15 秒确认时间，超时请求恢复。此功能仍在实验验证中。")
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    @ViewBuilder private func actions(for screen: DisplayRecord) -> some View {
        if screen.isActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("收拢窗口到此屏幕", systemImage: "rectangle.on.rectangle") { Task { await store.gather() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.isTrusted || store.isBusy)
                    Button("设为主屏幕") { Task { await store.makeMain() } }
                        .disabled(screen.isMain || store.isBusy || screen.isMirrored)
                }
                HStack {
                    Button("仅使用此屏幕…", systemImage: "display") {
                        disconnectID = nil
                        confirmingDisconnection = true
                    }
                    .disabled(!canDisconnect)
                    Menu("停用此屏幕…") {
                        ForEach(store.displays.filter { $0.isActive && $0.id != screen.id }) { destination in
                            Button("窗口移到 \(destination.name)") {
                                disconnectID = screen.id
                                store.selectedID = destination.id
                                confirmingDisconnection = true
                            }
                        }
                    }
                    .disabled(!canDisconnect)
                }
                Text("收拢普通窗口并保留合理尺寸。全屏和最小化窗口保持原状态。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button("重新连接屏幕", systemImage: "power") { Task { await store.reconnectSelected() } }
                .disabled(store.isBusy || !store.supportsDisconnection)
            Text("需要显示器仍与 Mac 连接。软件恢复失败时，请拔插连接线。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var canDisconnect: Bool {
        store.activeCount > 1 && store.isTrusted && !store.isBusy && store.supportsDisconnection && store.remainingSeconds == nil
    }

    private var permissionNotice: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text("允许管理其他应用的窗口").font(.headline)
                    Text("在系统设置中开启 LogicScreen 的辅助功能权限。授权后自动更新状态。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("前往授权") { store.requestPermission() }
            }.padding(6)
        }
    }

    private func recoveryNotice(seconds: Int) -> some View {
        GroupBox {
            HStack {
                Text("屏幕正常显示吗？\(seconds) 秒后恢复。")
                Spacer()
                Button("立即恢复") { Task { await store.restore() } }
                Button("保留配置") { store.keepConfiguration() }.buttonStyle(.borderedProminent)
            }.padding(6)
        }
    }
}
