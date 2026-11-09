import LogicScreenCore
import SwiftUI

struct ScreenMap: View {
    let displays: [DisplayRecord]
    @Binding var selectedID: String?

    private var active: [DisplayRecord] { displays.filter(\.isActive) }

    var body: some View {
        GeometryReader { geometry in
            let bounds = active.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = min((geometry.size.width - 30) / max(bounds.width, 1),
                            (geometry.size.height - 30) / max(bounds.height, 1))
            let offsetX = (geometry.size.width - bounds.width * scale) / 2
            let offsetY = (geometry.size.height - bounds.height * scale) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45))
                ForEach(active) { display in
                    let selected = display.id == selectedID
                    Button { selectedID = display.id } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.09))
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
                            VStack(spacing: 6) {
                                Text(display.name).font(.callout.weight(.medium)).lineLimit(1)
                                if display.isMain {
                                    Text("主屏幕").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.padding(8)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(1, display.frame.width * scale - 5), height: max(1, display.frame.height * scale - 5))
                    .offset(x: offsetX + (display.frame.minX - bounds.minX) * scale,
                            y: offsetY + (display.frame.minY - bounds.minY) * scale)
                    .accessibilityLabel("\(display.name)，\(display.isMain ? "主屏幕" : "扩展屏幕")")
                }
            }
        }
    }
}
