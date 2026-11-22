import AppKit
import CaptionCore
import Foundation

/// Most people start the captions a few minutes into the meeting, after the first words were missed. When a meeting app comes
/// to the front, Ieum offers to start them. It only looks at which app is in front, on this Mac; nothing is sent anywhere.
extension AppModel {
    func startWatchingMeetingApps() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontAppChanged(bundleID: id) }
        }
    }

    private func frontAppChanged(bundleID: String?) {
        guard let app = MeetingApps.app(forBundleID: bundleID) else { return }
        guard overlayVisible else { return }
        guard suggestionPolicy.shouldOffer(for: app, now: Date(), captionsRunning: isRunning || status == .starting, enabled: suggestsStart) else { return }
        startSuggestion = app
        // An offer nobody answered goes away by itself, so it never lingers over a finished meeting.
        suggestionExpiry?.cancel()
        suggestionExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            if !Task.isCancelled { self?.startSuggestion = nil }
        }
    }

    func acceptStartSuggestion() {
        endSuggestion()
        start()
    }

    func dismissStartSuggestion() { endSuggestion() }

    /// "Don't ask for this app".
    func muteStartSuggestion() {
        if let app = startSuggestion {
            suggestionPolicy.mute(app)
            Preferences.mutedMeetingApps = suggestionPolicy.muted
        }
        endSuggestion()
    }

    func setSuggestsStart(_ on: Bool) {
        suggestsStart = on
        Preferences.suggestsStart = on
        if !on { endSuggestion() }
    }

    /// Settings: ask again for the apps that were silenced.
    func resetMutedMeetingApps() {
        suggestionPolicy.unmuteAll()
        Preferences.mutedMeetingApps = []
    }

    var hasMutedMeetingApps: Bool { !suggestionPolicy.muted.isEmpty }

    private func endSuggestion() {
        suggestionExpiry?.cancel()
        suggestionExpiry = nil
        startSuggestion = nil
    }
}
