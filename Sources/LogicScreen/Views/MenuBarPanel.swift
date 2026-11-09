import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("LogicScreen", systemImage: "display.2").font(.headline)
                Spacer()
                Text("\(store.activeCount) 块屏幕").font(.caption).foregroundStyle(.secondary)
            }
            if let seconds = store.remainingSeconds {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(seconds) 秒后恢复原布局").font(.callout.weight(.medium))
                    HStack {
                        Button("立即恢复") { Task { await store.restore() } }
                        Button("保留配置") { store.keepConfiguration() }
                            .buttonStyle(.borderedProminent).disabled(store.isBusy)
                    }
                }
            } else {
                Text("收拢窗口到…").font(.caption).foregroundStyle(.secondary)
                ForEach(store.activeDisplays) { screen in
                    Button {
                        store.selectedID = screen.id
                        Task { await store.gather() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display").foregroundStyle(.tint)
                            Text(String(screen.name.prefix(20))).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.down.right.and.arrow.up.left").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(store.controlsLocked || !store.isTrusted || store.activeCount < 2)
                }
            }
            if !store.isTrusted {
                Button("开启窗口管理权限…") { showWorkspace(); store.requestPermission() }
                    .font(.callout)
            }
            if store.isBusy { ProgressView(store.phase?.title ?? "正在调整工作空间…").controlSize(.small) }
            Divider()
            HStack {
                Button("打开工作台", systemImage: "arrow.up.right.square") { showWorkspace() }
                Spacer()
                Button("恢复布局", systemImage: "arrow.uturn.backward") { Task { await store.restore() } }
                    .disabled(!store.canRestore || store.isBusy)
            }
            HStack {
                SettingsLink { Label("设置", systemImage: "gearshape") }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.disabled(store.isBusy)
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 330)
        .task { store.start() }
    }

    private func showWorkspace() {
        WorkspaceWindow.present(openWindow: openWindow)
    }
}
