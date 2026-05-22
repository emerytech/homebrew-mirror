import AppKit

// Renders Mirror's app icon (rounded-rect gradient + mirror) into an
// .iconset and packs it into AppIcon.icns via iconutil.

func drawIcon(px: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    // macOS app icons sit on a rounded square with a small margin.
    let inset = px * 0.08
    let body = rect.insetBy(dx: inset, dy: inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: px * 0.2, yRadius: px * 0.2)

    // Deep slate background so the bright mirror pops.
    NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.34, blue: 0.44, alpha: 1),
        NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1),
    ])!.draw(in: bg, angle: -90)

    // The mirror: a glossy silver/blue circle.
    let dia = px * 0.58
    let circleRect = NSRect(x: (px - dia)/2, y: (px - dia)/2, width: dia, height: dia)
    let mirror = NSBezierPath(ovalIn: circleRect)

    NSGradient(colors: [
        NSColor(srgbRed: 0.99, green: 0.99, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.70, green: 0.80, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.90, blue: 0.99, alpha: 1),
    ])!.draw(in: mirror, angle: 50)

    // Reflective highlight streaks, clipped to the circle.
    NSGraphicsContext.saveGraphicsState()
    mirror.addClip()
    let t = NSAffineTransform()
    t.translateX(by: px * 0.5, yBy: px * 0.5)
    t.rotate(byDegrees: -32)
    t.concat()
    NSColor.white.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: -px*0.5, y: px*0.04, width: px, height: px*0.085),
                 xRadius: px*0.04, yRadius: px*0.04).fill()
    NSColor.white.withAlphaComponent(0.30).setFill()
    NSBezierPath(roundedRect: NSRect(x: -px*0.5, y: px*0.18, width: px, height: px*0.045),
                 xRadius: px*0.022, yRadius: px*0.022).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Bright frame ring.
    NSColor.white.withAlphaComponent(0.9).setStroke()
    mirror.lineWidth = px * 0.028
    mirror.stroke()
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in specs {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(px: CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: iconset.appendingPathComponent(name + ".png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path,
                  "-o", here.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("AppIcon.icns generated")
