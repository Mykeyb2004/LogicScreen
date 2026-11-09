import AppKit
import SwiftUI
import LogicScreenCore

struct MigrationSheet: View {
    @Bindable var store: WorkspaceStore
    let plan: DisplayChangePlan
    @AppStorage("confirmationDuration") private var confirmationDuration = 15
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "display.2").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("准备切换工作空间").font(.title2.weight(.semibold))
                    Text("先安顿窗口，再停用屏幕。").foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("将停用").font(.caption).foregroundStyle(.secondary)
                    ForEach(plan.sources) { Text($0.name).font(.callout.weight(.medium)).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("窗口移至 · 保持开启").font(.caption).foregroundStyle(.secondary)
                    Text(plan.target.name).font(.callout.weight(.semibold)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.workspaceCard()
            VStack(alignment: .leading, spacing: 13) {
                checkRow("\(plan.readiness.movable) 个窗口可以迁移", symbol: "rectangle.on.rectangle", ok: true)
                if plan.readiness.blocked > 0 {
                    checkRow("\(plan.readiness.blocked) 个窗口需要先处理", symbol: "exclamationmark.circle", ok: false)
                    let affectedPIDs = Set(plan.inventory.windows.filter { plan.sourceIDs.contains($0.displayID) && $0.restriction != nil }.map(\.applicationPID))
                    Text(affectedPIDs.sorted().map { NSRunningApplication(processIdentifier: $0)?.localizedName ?? "应用 \($0)" }.joined(separator: "、") + "：请退出全屏、还原最小化窗口，或手动移走不可移动窗口。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else { checkRow("待停用屏幕没有已知的特殊窗口", symbol: "checkmark.shield", ok: true) }
                if plan.readiness.unreadableApplications > 0 {
                    checkRow("\(plan.readiness.unreadableApplications) 个应用暂时无法读取", symbol: "exclamationmark.circle", ok: false)
                    Text("请等待应用响应或退出相关应用，再重新检查。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("执行时会再次迁移和核验；未通过核验则保持屏幕开启。切换后有 \(confirmationDuration) 秒确认时间，超时自动恢复。屏幕停用为实验功能。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("重新检查") {
                    Task { await store.prepareFocus(targetID: plan.target.id, sourceIDs: plan.sourceIDs) }
                }.disabled(store.isPreparing)
                if store.isPreparing { ProgressView().controlSize(.small) }
                Spacer()
                Button("迁移窗口并停用屏幕") { Task { await store.focus(using: plan) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.readiness.canProceed || store.isPreparing)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 550)
        .interactiveDismissDisabled(store.isPreparing)
    }

    private func checkRow(_ title: String, symbol: String, ok: Bool) -> some View {
        Label(title, systemImage: symbol).font(.callout)
            .foregroundStyle(ok ? Color.primary : Color.orange)
    }
}
