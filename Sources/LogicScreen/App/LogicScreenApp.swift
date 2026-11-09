import AppKit
import SwiftUI
import OSLog

@main
struct LogicScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup("LogicScreen", id: "workspace") {
            ContentView(store: store)
                .task { store.start() }
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("收拢窗口到所选屏幕") { Task { await store.gather() } }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!store.isTrusted || store.isBusy || store.selected?.isActive != true)
                Button("恢复布局") { Task { await store.restore() } }
                    .keyboardShortcut("r", modifiers: [.command, .option, .control])
                    .disabled(!store.canRestore || store.isBusy)
            }
        }

        MenuBarExtra("LogicScreen", systemImage: "display.2") {
            MenuContent(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fixtureWindow: NSWindow?

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
}

private struct MenuContent: View {
    let store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 LogicScreen") {
            openWindow(id: "workspace")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        ForEach(store.displays.filter(\.isActive)) { screen in
            Button("收拢到 \(String(screen.name.prefix(16)))") {
                store.selectedID = screen.id
                Task { await store.gather() }
            }
            .disabled(store.isBusy || !store.isTrusted)
        }
        Divider()
        Button("恢复布局  ⌃⌥⌘R") { Task { await store.restore() } }
            .disabled(!store.canRestore || store.isBusy)
        Button("退出 LogicScreen") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
