import AppKit

@MainActor
final class ScreenLabels {
    private var panels: [NSPanel] = []
    private var dismissTask: Task<Void, Never>?

    func show() {
        dismiss()
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = NSRect(x: screen.frame.midX - 150, y: screen.frame.midY - 65, width: 300, height: 130)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 18
            let label = NSTextField(labelWithString: "\(index + 1)  ·  \(screen.localizedName)")
            label.font = .systemFont(ofSize: 23, weight: .semibold)
            label.alignment = .center
            label.frame = NSRect(x: 12, y: 45, width: 276, height: 36)
            effect.addSubview(label)
            panel.contentView = effect
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}
