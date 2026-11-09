#!/usr/bin/env swift
import AppKit

// Draw vector artwork at every icon size, so the bundle needs no image dependencies.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let variants = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in variants {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let bounds = NSRect(x: 40, y: 40, width: 944, height: 944)
    let background = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.45, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.15, green: 0.22, blue: 0.65, alpha: 1))!.draw(in: background, angle: -65)
    func monitor(_ frame: NSRect, alpha: CGFloat) {
        NSColor.white.withAlphaComponent(alpha).setStroke()
        let outline = NSBezierPath(roundedRect: frame, xRadius: 25, yRadius: 25)
        outline.lineWidth = 26
        outline.stroke()
        let base = NSBezierPath()
        base.move(to: NSPoint(x: frame.midX, y: frame.minY))
        base.line(to: NSPoint(x: frame.midX, y: frame.minY - 58))
        base.move(to: NSPoint(x: frame.midX - 64, y: frame.minY - 58))
        base.line(to: NSPoint(x: frame.midX + 64, y: frame.minY - 58))
        base.lineWidth = 25
        base.lineCapStyle = .round
        base.stroke()
    }
    monitor(NSRect(x: 162, y: 470, width: 370, height: 257), alpha: 0.53)
    monitor(NSRect(x: 474, y: 300, width: 390, height: 277), alpha: 1)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 255, y: 384))
    arrow.curve(to: NSPoint(x: 401, y: 275), controlPoint1: NSPoint(x: 250, y: 295), controlPoint2: NSPoint(x: 310, y: 275))
    arrow.move(to: NSPoint(x: 365, y: 317))
    arrow.line(to: NSPoint(x: 409, y: 275))
    arrow.line(to: NSPoint(x: 365, y: 234))
    arrow.lineWidth = 26
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor.white.setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
