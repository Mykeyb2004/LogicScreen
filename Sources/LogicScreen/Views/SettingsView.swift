import SwiftUI

struct SettingsView: View {
    let store: WorkspaceStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("confirmationDuration") private var confirmationDuration = 15

    var body: some View {
        Form {
            Section("工作台") {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                LabeledContent("关闭主窗口") { Text("在菜单栏继续运行").foregroundStyle(.secondary) }
            }
            Section {
                Picker("切换确认时间", selection: $confirmationDuration) {
                    Text("15 秒").tag(15)
                    Text("20 秒").tag(20)
                    Text("30 秒").tag(30)
                }
                LabeledContent("全局恢复快捷键") { Text("⌃ ⌥ ⌘ R").font(.system(.body, design: .monospaced)) }
                LabeledContent("退出应用") { Text("恢复本次记录的布局与窗口").foregroundStyle(.secondary) }
            } header: { Text("屏幕恢复") } footer: {
                Text("未在确认时间内保留配置，将自动恢复。恢复记录仅保存在本次运行中。")
            }
            Section("窗口管理") {
                LabeledContent("辅助功能权限") {
                    if store.isTrusted { Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { Button("前往授权") { store.requestPermission() } }
                }
                Text("窗口预览只统计应用与数量，不读取窗口标题，也不截取屏幕内容。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "display.2").font(.title).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LogicScreen").font(.headline)
                        Text("0.2 · 一个更专注的多屏工作空间").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("屏幕停用为实验功能，表示从桌面布局中移除，不保证硬件断电。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 490, height: 535)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}
