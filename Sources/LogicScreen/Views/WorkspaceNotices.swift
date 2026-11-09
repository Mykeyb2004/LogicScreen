import SwiftUI

struct PermissionBanner: View {
    let store: WorkspaceStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "hand.raised.square.fill").font(.system(size: 30)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text("开启窗口管理，从这里开始").font(.headline)
                Text("在辅助功能中允许 LogicScreen，即可预览和迁移其他应用的窗口。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("前往授权", systemImage: "arrow.up.right") { store.requestPermission() }
                .buttonStyle(.borderedProminent)
        }
        .workspaceCard()
    }
}

struct RecoveryBanner: View {
    let store: WorkspaceStore
    let seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.tint.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(seconds) / CGFloat(store.countdownDuration))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(seconds)").font(.title3.monospacedDigit().weight(.semibold))
                }.frame(width: 46, height: 46).accessibilityLabel("\(seconds) 秒后自动恢复")
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前屏幕显示正常吗？").font(.headline)
                    Text("\(seconds) 秒内未确认，将自动恢复原来的屏幕和窗口。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("立即恢复", systemImage: "arrow.uturn.backward") { Task { await store.restore() } }
                Spacer()
                Button("显示正常，保留配置", systemImage: "checkmark") { store.keepConfiguration() }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy)
            }
        }
        .workspaceCard()
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.tint.opacity(0.4), lineWidth: 1) }
    }
}

struct OperationProgress: View {
    let phase: WorkspacePhase

    var body: some View {
        HStack(spacing: 10) {
            ForEach(WorkspacePhase.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    if step == phase { ProgressView().controlSize(.mini) }
                    else { Image(systemName: step.rawValue < phase.rawValue ? "checkmark.circle.fill" : "circle") }
                    Text(step.title).font(.caption.weight(step == phase ? .semibold : .regular))
                }
                .foregroundStyle(step.rawValue <= phase.rawValue ? Color.accentColor : Color.secondary)
                if step != .settling { Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary); Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
