import SwiftUI

struct PermissionHelpView: View {
    let store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("已开启，但权限仍未生效？", systemImage: "lock.shield").font(.title2.weight(.semibold))
            Text("macOS 会核验具体应用的签名。应用更新后，设置中的开关可能仍显示开启，但保存的是旧版本的授权。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 16) {
                step("1", "移除旧条目", "在“隐私与安全性 → 辅助功能”中选中 LogicScreen，点击减号移除。")
                step("2", "重新添加当前应用", "点击加号，添加正在运行的这份 LogicScreen.app，并开启开关。下方按钮可在访达中定位它。")
                step("3", "回到工作台重新检测", "应用会自动检查权限，也可以点击“重新检测”。如果仍未生效，请退出后重新打开应用。")
            }
            if store.signingInfo.isAdHoc == true {
                Text("当前为临时签名的开发版本，重新构建后可能需要再次添加。使用固定证书签名可以避免授权随构建失效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("显示当前应用", systemImage: "folder") { store.revealCurrentApplication() }
                Button("打开辅助功能") { store.openAccessibilitySettings() }
                Spacer()
                Button("重新检测") {
                    Task {
                        await store.recheckPermission()
                        if store.isTrusted { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                if store.isTrusted { Label("当前版本的权限已生效", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Text("以系统对当前版本的实际权限检查结果为准。").foregroundStyle(.secondary) }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.font(.caption)
        }
        .padding(26).frame(width: 590)
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.callout.weight(.semibold)).frame(width: 26, height: 26)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
