import Foundation
import Testing

@testable import CaptionCore

@Suite("Update check")
struct UpdateCheckTests {
    private func feed(_ version: String = "0.3.0", url: String = "https://github.com/stoneidev/ieum/releases/download/v0.3.0/Ieum.dmg",
                      sha: String = String(repeating: "a", count: 64), minimum: String? = "14.0") -> UpdateFeed {
        UpdateFeed(version: version, url: URL(string: url)!, sha256: sha, minimumMacOS: minimum)
    }

    private func evaluate(_ feed: UpdateFeed, current: String = "0.2.9", skipped: String? = nil, macOS: String = "26.0", manual: Bool = false) -> UpdateCheck.Outcome {
        UpdateCheck.evaluate(feed: feed, current: current, skipped: skipped, macOS: macOS, userInitiated: manual)
    }

    @Test func offersANewerVersion() {
        #expect(evaluate(feed()) == .available(feed()))
    }

    @Test func saysUpToDateForTheSameOrAnOlderVersion() {
        #expect(evaluate(feed("0.2.9")) == .upToDate)
        #expect(evaluate(feed("0.2.8")) == .upToDate)
    }

    @Test func aSkippedVersionStaysQuietUntilAskedForByHand() {
        #expect(evaluate(feed(), skipped: "0.3.0") == .skipped(feed()))
        #expect(evaluate(feed(), skipped: "0.3.0", manual: true) == .available(feed()))
        #expect(evaluate(feed("0.3.1"), skipped: "0.3.0") == .available(feed("0.3.1")))
    }

    @Test func aVersionThatNeedsANewerMacOSIsNotOffered() {
        #expect(evaluate(feed(minimum: "26.0"), macOS: "15.2") == .needsNewerMacOS(feed(minimum: "26.0"), required: "26.0"))
        #expect(evaluate(feed(minimum: "14.0"), macOS: "14.0") == .available(feed(minimum: "14.0")))
    }

    @Test func refusesAFeedItCannotTrust() {
        #expect(evaluate(feed("x")) == .invalid)
        #expect(evaluate(feed(url: "http://github.com/a/Ieum.dmg")) == .invalid)          // not https
        #expect(evaluate(feed(url: "https://evil.example.com/Ieum.dmg")) == .invalid)     // not a release host
        #expect(evaluate(feed(sha: "abc")) == .invalid)
        #expect(evaluate(feed(sha: String(repeating: "A", count: 64))) == .invalid)       // must be lowercase hex
    }

    @Test func aLocalFeedIsAllowedOnlyWhenAskedFor() {
        let local = feed(url: "http://localhost:8765/Ieum.dmg")
        #expect(UpdateCheck.evaluate(feed: local, current: "0.2.9", skipped: nil, macOS: "26.0", userInitiated: true) == .invalid)
        #expect(UpdateCheck.evaluate(feed: local, current: "0.2.9", skipped: nil, macOS: "26.0", userInitiated: true, allowLocalHost: true) == .available(local))
    }

    @Test func checksOnceADayAtMost() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))     // a clock set back
    }

    @Test func notesFallBackToEnglish() {
        var value = feed()
        value.notes = ["en": ["Fixed a bug"], "ko": ["버그를 고쳤습니다"]]
        #expect(UpdateCheck.notes(of: value, language: "ko") == ["버그를 고쳤습니다"])
        #expect(UpdateCheck.notes(of: value, language: "ja") == ["Fixed a bug"])
        value.notes = nil
        #expect(UpdateCheck.notes(of: value, language: "en").isEmpty)
    }

    @Test func theFeedDecodesFromJSON() throws {
        let json = #"{"version":"0.3.0","url":"https://github.com/stoneidev/ieum/releases/download/v0.3.0/Ieum.dmg","sha256":"\#(String(repeating: "b", count: 64))","size":1500000,"minimumMacOS":"14.0","notes":{"en":["a"],"ko":["가"]}}"#
        let decoded = try JSONDecoder().decode(UpdateFeed.self, from: Data(json.utf8))
        #expect(decoded.version == "0.3.0" && decoded.size == 1_500_000 && decoded.notes?["ko"] == ["가"])
    }
}
