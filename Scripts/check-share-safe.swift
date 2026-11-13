// Checks, on this Mac, whether a window with sharingType = .none is left out of a ScreenCaptureKit capture (what Zoom, Meet and
// Teams use to share the screen). It opens a small magenta window, captures the display and reads ONE pixel in the middle of that
// window; nothing else of the capture is looked at or saved.
//
//   swiftc -O Scripts/check-share-safe.swift -o /tmp/check-share-safe && /tmp/check-share-safe none      # hidden: pixel is not magenta
//   /tmp/check-share-safe readOnly                                                                         # control: pixel is magenta
//
// Needs the Screen & System Audio Recording permission for the terminal that runs it.
import AppKit
import ScreenCaptureKit

let mode = CommandLine.arguments.dropFirst().first ?? "none"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let rect = NSRect(x: screen.frame.minX + 40, y: screen.frame.minY + 120, width: 160, height: 80)
let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
window.isOpaque = true
window.level = .floating
window.sharingType = mode == "none" ? .none : .readOnly
window.orderFrontRegardless()

Task { @MainActor in
    try? await Task.sleep(for: .seconds(1.5))
    do {
        let content = try await SCShareableContent.current
        let listed = content.windows.contains { $0.windowID == CGWindowID(window.windowNumber) }
        guard let display = content.displays.first(where: { $0.displayID == (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) }) ?? content.displays.first else { print("no display"); exit(1) }
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width); config.height = Int(screen.frame.height)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        // the middle of our window, in image pixels (origin top-left)
        let x = Int(rect.midX - screen.frame.minX), y = Int(screen.frame.maxY - rect.midY)
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let data = crop.dataProvider?.data, let p = CFDataGetBytePtr(data) else { print("no pixel"); exit(1) }
        let (b, g, r) = (p[0], p[1], p[2])   // BGRA
        let magenta = r > 200 && b > 200 && g < 60
        print("sharingType=\(mode) windowListedBySCK=\(listed) pixelIsMagenta(window visible to capture)=\(magenta) rgb=(\(r),\(g),\(b))")
    } catch { print("capture failed: \(error)") }
    exit(0)
}
app.run()
