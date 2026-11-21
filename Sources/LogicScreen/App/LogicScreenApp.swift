import AppKit
import SwiftUI
import OSLog

@main
struct LogicScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("LogicScreen", id: "workspace") { workspaceContent }
        .defaultSize(width: 1040, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("收拢窗口到所选屏幕") { Task { await store.gather() } }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!store.isTrusted || store.controlsLocked || store.selected?.isActive != true || store.activeCount < 2)
                Button("恢复布局") { Task { await store.restore() } }
                    .keyboardShortcut("r", modifiers: [.command, .option, .control])
                    .disabled(!store.canRestore || store.isBusy)
            }
        }

        MenuBarExtra("LogicScreen", systemImage: "display.2") {
            MenuBarPanel(store: store)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(store: store) }
    }

    private var workspaceContent: some View {
        ContentView(store: store)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .onAppear { delegate.store = store }
            .task { store.start() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fixtureWindow: NSWindow?
    weak var store: WorkspaceStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard !store.isBusy, !store.isPreparing else {
            NSApp.activate(ignoringOtherApps: true)
            return .terminateCancel
        }
        guard store.canRestore else { return .terminateNow }
        Task { @MainActor in
            await store.restore()
            if store.canRestore {
                let alert = NSAlert()
                alert.messageText = "部分布局或窗口尚未恢复"
                alert.informativeText = "可以返回工作台再次恢复；立即退出后，本次窗口位置记录将丢失。"
                alert.addButton(withTitle: "返回工作台")
                alert.addButton(withTitle: "仍然退出")
                NSApp.activate(ignoringOtherApps: true)
                NSApp.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            } else { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Logger(subsystem: "dev.logicscreen.app", category: "Lifecycle").info("Application launched")
        if CommandLine.arguments.contains("--validation-fixture") {
            let window = NSWindow(contentRect: NSRect(x: 120, y: 160, width: 600, height: 360),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "LogicScreen 验证窗口"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VStack(spacing: 12) {
                Image(systemName: "checkmark.rectangle.stack").font(.system(size: 34)).foregroundStyle(.tint)
                Text("窗口迁移验证").font(.title2)
                Text("此窗口仅用于验证坐标和恢复。完成后可以关闭。 ").foregroundStyle(.secondary)
            }.frame(width: 600, height: 360))
            window.makeKeyAndOrderFront(nil)
            fixtureWindow = window
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let window = WorkspaceWindow.existing() else { return true }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return false
    }
}
