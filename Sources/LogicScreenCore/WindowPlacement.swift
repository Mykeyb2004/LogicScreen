import Foundation
import CoreGraphics

public enum WindowPlacement {
    public static func owningDisplay(for window: CGRect, displays: [DisplayRecord]) -> DisplayRecord? {
        displays.filter { $0.isActive && area(window.intersection($0.frame)) > 0 }
            .max { area(window.intersection($0.frame)) < area(window.intersection($1.frame)) }
    }

    public static func movedFrame(_ window: CGRect, from source: CGRect, to destination: CGRect,
                                  canResize: Bool) -> CGRect {
        guard destination.width > 0, destination.height > 0 else { return window }
        let size = canResize
            ? CGSize(width: min(window.width, destination.width), height: min(window.height, destination.height))
            : window.size
        let xFraction = fraction(window.minX - source.minX, available: source.width - window.width)
        let yFraction = fraction(window.minY - source.minY, available: source.height - window.height)
        return CGRect(x: destination.minX + xFraction * max(0, destination.width - size.width),
                      y: destination.minY + yFraction * max(0, destination.height - size.height),
                      width: size.width, height: size.height)
    }

    public static func appKitToQuartz(_ rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func fraction(_ value: CGFloat, available: CGFloat) -> CGFloat {
        available > 0 ? min(1, max(0, value / available)) : 0
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
