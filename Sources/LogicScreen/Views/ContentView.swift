import SwiftUI
import LogicScreenCore

struct ContentView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        NavigationSplitView {
            DisplaySidebar(store: store)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let seconds = store.remainingSeconds {
                            RecoveryBanner(store: store, seconds: seconds)
                        }
                        if !store.isTrusted { PermissionBanner(store: store) }
                        if let screen = store.selected {
                            DisplayDetail(store: store, screen: screen)
                        } else {
                            ContentUnavailableView("连接你的第一块屏幕", systemImage: "display",
                                                   description: Text("连接显示器后，屏幕会自动出现在这里。"))
                                .frame(maxWidth: .infinity, minHeight: 340)
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                }
                WorkspaceStatus(store: store)
            }
            .frame(minWidth: 600, minHeight: 640)
            .navigationTitle("屏幕工作台")
            .toolbar {
                ToolbarItemGroup {
                    Button("识别屏幕", systemImage: "number.square") { store.showLabels() }
                        .help("在所有屏幕上显示编号与名称")
                    Button("刷新窗口", systemImage: "arrow.clockwise") { Task { await store.reloadWindows() } }
                        .disabled(store.isBusy || store.isLoadingWindows)
                    Button("恢复布局", systemImage: "arrow.uturn.backward") { Task { await store.restore() } }
                        .disabled(!store.canRestore || store.isBusy)
                        .help("恢复屏幕排列和本次记录的窗口位置（⌃⌥⌘R）")
                }
            }
        }
        .sheet(item: $store.plan) { plan in MigrationSheet(store: store, plan: plan) }
    }
}

struct DisplaySidebar: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        List(selection: $store.selectedID) {
            Section("正在使用 · \(store.activeCount)") {
                ForEach(store.activeDisplays) { display in row(display) }
            }
            let inactive = store.displays.filter { !$0.isActive }
            if !inactive.isEmpty {
                Section("已停用 / 未连接") { ForEach(inactive) { display in row(display) } }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LogicScreen")
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 270)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 7) {
                Image(systemName: store.isTrusted ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(store.isTrusted ? Color.green : Color.orange)
                Text(store.isTrusted ? "窗口管理已就绪" : "等待辅助功能授权").font(.caption)
                Spacer(minLength: 0)
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置")
                    .accessibilityLabel("设置")
            }
            .foregroundStyle(.secondary).padding(16)
        }
    }

    private func row(_ display: DisplayRecord) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(display.name).lineLimit(1)
                Text(display.isActive ? (display.isMain ? "主屏幕" : "扩展屏幕") : "可尝试重新连接")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } icon: { Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display") }
        .tag(display.id)
    }
}

struct WorkspaceStatus: View {
    let store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 9) {
                if store.isBusy || store.isPreparing {
                    ProgressView().controlSize(.small).padding(.top, 2)
                } else {
                    Image(systemName: store.statusIsError ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(store.statusIsError ? Color.orange : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.isPreparing ? "正在检查窗口，屏幕保持开启…" : store.status)
                        .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("随时恢复 ⌃⌥⌘R · 关闭窗口后仍可从菜单栏使用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if store.statusIsError && store.canRestore {
                    Button("恢复布局") { Task { await store.restore() } }.disabled(store.isBusy)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }
}
