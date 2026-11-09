import AppKit
import SwiftUI
import LogicScreenCore

struct WindowPreviewList: View {
    let store: WorkspaceStore
    let target: DisplayRecord
    @State private var expanded = false

    private var windows: [WindowPreview] {
        store.inventory?.windows.filter { $0.displayID != target.id } ?? []
    }
    private var pids: [Int32] { Array(Set(windows.map(\.applicationPID))).sorted { appName($0).localizedStandardCompare(appName($1)) == .orderedAscending } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("窗口预览").font(.headline)
                if let inventory = store.inventory {
                    Text("其他屏幕 · \(windows.count) 个").font(.caption).foregroundStyle(.secondary)
                    if !inventory.unreadablePIDs.isEmpty {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            .help("部分应用无法读取，停用前需要重新检查")
                    }
                }
                Spacer()
                if store.isLoadingWindows { ProgressView().controlSize(.mini) }
            }
            if !store.isTrusted {
                HStack(spacing: 12) {
                    Image(systemName: "macwindow.on.rectangle").font(.title).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("授权后，先看看有哪些窗口需要移动").font(.callout)
                        Text("按应用显示数量，不读取窗口标题或文档内容。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 7)
            } else if let error = store.inventoryError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
            } else if store.inventory == nil {
                Text("正在读取窗口…").font(.callout).foregroundStyle(.secondary)
            } else if windows.isEmpty {
                Label("其他屏幕上暂无可识别的窗口", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(expanded ? pids : Array(pids.prefix(4)), id: \.self) { pid in
                    let appWindows = windows.filter { $0.applicationPID == pid }
                    let blocked = appWindows.filter { $0.restriction != nil }
                    HStack(spacing: 10) {
                        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                            Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                        } else { Image(systemName: "app").frame(width: 28, height: 28).foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appName(pid)).font(.callout)
                            let sources = store.displays.filter { display in appWindows.contains { $0.displayID == display.id } }
                            Text(sources.map(\.name).joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if !blocked.isEmpty {
                            Text("\(blocked.count) 个需处理").font(.caption).foregroundStyle(.orange)
                                .help("全屏、最小化或不可移动窗口会阻止停用其所在屏幕")
                        }
                        Text("\(appWindows.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if pids.count > 4 {
                    Button(expanded ? "收起列表" : "显示全部 \(pids.count) 个应用") { expanded.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
                Text("普通收拢会跳过全屏、最小化和不可移动窗口；停用屏幕前会逐项核验。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).workspaceCard()
    }

    private func appName(_ pid: Int32) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "应用 \(pid)"
    }
}
