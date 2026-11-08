import AppKit
import SwiftUI

/// A normal, closable window that hosts SwiftUI content for the settings and the setup screen.
/// The app has no Dock icon, so showing one means activating the app first.
@MainActor
final class AuxiliaryWindow {
    private let makeContent: () -> NSView
    private let title: () -> String
    private var window: NSWindow?

    init(title: @escaping () -> String, content: @escaping () -> NSView) {
        self.title = title
        makeContent = content
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSViewController())
            window.contentView = makeContent()
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = title()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
