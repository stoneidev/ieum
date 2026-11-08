// Draws the app icon: smoked glass, a muted line of caption above a bright one, and the amber "live" dot.
// Usage: swift Scripts/make-icon.swift Resources/App/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    // macOS icons leave a margin around the artwork.
    let body = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSGradient(colors: [color(0x2B3038), color(0x14171A)])?.draw(in: shape, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Soft top highlight, the "glass".
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])?
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        let rect = NSRect(x: body.minX + body.width * x, y: body.minY + body.height * y, width: body.width * w, height: body.height * h)
        c.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
    // Interim text (muted), then confirmed text (bright), with the live dot beside it.
    bar(0.17, 0.52, 0.50, 0.075, color(0x9CA3AB))
    bar(0.17, 0.34, 0.66, 0.095, color(0xF4F2EE))
    let dot = NSRect(x: body.minX + body.width * 0.17, y: body.minY + body.height * 0.17, width: body.width * 0.075, height: body.width * 0.075)
    color(0xFFB224).setFill()
    NSBezierPath(ovalIn: dot).fill()
    image.unlockFocus()

    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size: size).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", output]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(output)" : "iconutil failed")
