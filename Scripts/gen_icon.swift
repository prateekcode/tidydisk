// Generates AppIcon.icns: purple gradient rounded-rect with a sparkle-clean symbol.
// Usage: swift Scripts/gen_icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetPath = outputDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: content inset ~10% each side, continuous-corner rect
    let inset = size * 0.10
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.185, yRadius: size * 0.185)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.72, green: 0.28, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.36, green: 0.13, blue: 0.60, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.04, blue: 0.28, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -60)

    // inner highlight ring
    NSColor.white.withAlphaComponent(0.25).setStroke()
    let ringPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.008, dy: size * 0.008),
                                xRadius: size * 0.18, yRadius: size * 0.18)
    ringPath.lineWidth = size * 0.008
    ringPath.stroke()

    // symbol
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let scale = (size * 0.52) / max(symbolSize.width, symbolSize.height)
        let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawSize))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]

for (pixels, name) in sizes {
    let rep = drawIcon(size: CGFloat(pixels))
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(name).png"))
}
print("iconset written to \(iconsetPath)")
