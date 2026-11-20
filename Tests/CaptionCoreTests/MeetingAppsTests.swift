import Foundation
import Testing

@testable import CaptionCore

@Suite("Meeting app suggestion")
struct MeetingAppsTests {
    private let zoom = MeetingApps.app(forBundleID: "us.zoom.xos")!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func knowsTheCommonMeetingApps() {
        #expect(MeetingApps.app(forBundleID: "us.zoom.xos")?.name == "Zoom")
        #expect(MeetingApps.app(forBundleID: "com.microsoft.teams2")?.name == "Microsoft Teams")
        #expect(MeetingApps.app(forBundleID: "com.apple.Safari") == nil)
        #expect(MeetingApps.app(forBundleID: nil) == nil)
    }

    @Test func offersOnceAndThenWaits() {
        var policy = StartSuggestionPolicy()
        let first = policy.shouldOffer(for: zoom, now: now, captionsRunning: false, enabled: true)
        let soon = policy.shouldOffer(for: zoom, now: now.addingTimeInterval(60), captionsRunning: false, enabled: true)
        let later = policy.shouldOffer(for: zoom, now: now.addingTimeInterval(31 * 60), captionsRunning: false, enabled: true)
        #expect(first && !soon && later)
    }

    @Test func neverWhileCaptionsRunOrWhenSwitchedOff() {
        var policy = StartSuggestionPolicy()
        let running = policy.shouldOffer(for: zoom, now: now, captionsRunning: true, enabled: true)
        let off = policy.shouldOffer(for: zoom, now: now, captionsRunning: false, enabled: false)
        // neither attempt used up the offer
        let ok = policy.shouldOffer(for: zoom, now: now, captionsRunning: false, enabled: true)
        #expect(!running && !off && ok)
    }

    @Test func aMutedAppIsNeverOffered() {
        var policy = StartSuggestionPolicy()
        policy.mute(zoom)
        let muted = policy.shouldOffer(for: zoom, now: now, captionsRunning: false, enabled: true)
        policy.unmuteAll()
        let again = policy.shouldOffer(for: zoom, now: now, captionsRunning: false, enabled: true)
        #expect(!muted && again)
    }

    @Test func twoTeamsAppsCountAsOne() {
        var policy = StartSuggestionPolicy()
        let new = MeetingApps.app(forBundleID: "com.microsoft.teams2")!
        let old = MeetingApps.app(forBundleID: "com.microsoft.teams")!
        let first = policy.shouldOffer(for: new, now: now, captionsRunning: false, enabled: true)
        let second = policy.shouldOffer(for: old, now: now, captionsRunning: false, enabled: true)
        #expect(first && !second)
    }
}
