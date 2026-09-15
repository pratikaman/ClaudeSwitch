import AppKit

// Gauge's vector mark, rendered at every macOS icon size. No external libraries.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let variants = [(16, false), (16, true), (32, false), (32, true), (128, false),
                (128, true), (256, false), (256, true), (512, false), (512, true)]
for (points, retina) in variants {
    let pixels = points * (retina ? 2 : 1)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 220, yRadius: 220)
    NSColor(red: 0.075, green: 0.086, blue: 0.082, alpha: 1).setFill()
    tile.fill()
    NSColor.white.withAlphaComponent(0.11).setStroke()
    tile.lineWidth = 2
    tile.stroke()
    for (index, height) in [240.0, 490.0, 350.0].enumerated() {
        NSColor(red: 0.73, green: 0.85, blue: 0.77, alpha: index == 2 ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 251 + Double(index) * 177, y: 267, width: 130, height: height),
                     xRadius: 38, yRadius: 38).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = retina ? "@2x" : ""
    try rep.representation(using: .png, properties: [:])!
        .write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
