import AppKit
import SwiftUI

/// Keep a single workspace when the menu bar or Dock brings the utility forward.
@MainActor
enum WorkspaceWindow {
    static func existing() -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue.hasPrefix("workspace-AppWindow-") == true || $0.title == "屏幕工作台"
        }
    }

    static func present(openWindow: OpenWindowAction) {
        if let window = existing() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else { openWindow(id: "workspace") }
        NSApp.activate(ignoringOtherApps: true)
    }
}
