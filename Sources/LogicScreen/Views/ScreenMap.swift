import SwiftUI
import LogicScreenCore

struct ScreenMap: View {
    let displays: [DisplayRecord]
    @Binding var selectedID: String?
    let inventory: WindowInventory?

    private var active: [DisplayRecord] { displays.filter(\.isActive) }

    var body: some View {
        GeometryReader { geometry in
            let bounds = active.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = max(0.001, min((geometry.size.width - 64) / max(bounds.width, 1),
                                     (geometry.size.height - 48) / max(bounds.height, 1)))
            let offsetX = (geometry.size.width - bounds.width * scale) / 2
            let offsetY = (geometry.size.height - bounds.height * scale) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.045).gradient)
                ForEach(Array(active.enumerated()), id: \.element.id) { index, display in
                    let selected = display.id == selectedID
                    Button { selectedID = display.id } label: {
                        monitor(display, number: index + 1, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(1, display.frame.width * scale - 7), height: max(1, display.frame.height * scale - 7))
                    .offset(x: offsetX + (display.frame.minX - bounds.minX) * scale,
                            y: offsetY + (display.frame.minY - bounds.minY) * scale)
                    .help("选择 \(display.name)")
                    .accessibilityLabel("\(display.name)，\(display.isMain ? "主屏幕" : "扩展屏幕")\(selected ? "，已选择" : "")")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    private func monitor(_ display: DisplayRecord, number: Int, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1)
            VStack(spacing: 8) {
                HStack {
                    Text(String(number)).font(.caption.weight(.semibold))
                    Spacer()
                    if display.isMain { Image(systemName: "menubar.rectangle").help("主屏幕") }
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }
                Spacer(minLength: 0)
                Text(display.name).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                if let inventory {
                    let count = inventory.windows.filter { $0.displayID == display.id }.count
                    Text("\(count) 个窗口").font(.caption).foregroundStyle(.secondary)
                } else { Text(display.isMain ? "主屏幕" : "扩展屏幕").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.padding(12)
        }
    }
}
