import AppKit

/// Keeps Ieum's own windows out of what screen sharing and recording send, unless the person turned that off. The overlay
/// does it itself; this covers the settings, setup, "What's new" and update windows, which can show the same words.
@MainActor
enum ScreenShare {
    static func protect(_ window: NSWindow) {
        window.sharingType = Preferences.hidesFromSharing ? .none : .readOnly
    }

    /// After the setting changed: every window the app has now.
    static func refreshAll() {
        NSApp.windows.forEach(protect)
    }
}
