import Testing

@testable import CaptionCore

@Suite("What's new")
struct WhatsNewTests {
    private let introduced = ["0.2.4", "0.2.6", "0.2.7", "0.2.8"]

    @Test func versionsCompareNumberByNumber() {
        #expect(AppVersion("0.2.10")! > AppVersion("0.2.9")!)
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(AppVersion("0.3.0")! > AppVersion("0.2.99")!)
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func showsTheHighlightsSinceTheLastSeenVersion() {
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.7", current: "0.2.8", isFirstInstall: false) == [3])
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.5", current: "0.2.8", isFirstInstall: false) == [1, 2, 3])
    }

    @Test func nothingForTheSameVersionADowngradeOrAFirstInstall() {
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.8", current: "0.2.8", isFirstInstall: false).isEmpty)
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.8", current: "0.2.6", isFirstInstall: false).isEmpty)
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: nil, current: "0.2.8", isFirstInstall: true).isEmpty)
    }

    @Test func unknownLastSeenCountsAsTheBaseline() {
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: nil, current: "0.2.8", isFirstInstall: false) == [0, 1, 2, 3])
    }

    @Test func highlightsFromTheFutureAreNotShown() {
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.3", current: "0.2.6", isFirstInstall: false) == [0, 1])
    }

    @Test func unreadableVersionsShowNothing() {
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "x", current: "0.2.8", isFirstInstall: false).isEmpty)
        #expect(WhatsNew.pending(introduced: introduced, lastSeen: "0.2.3", current: "dev", isFirstInstall: false).isEmpty)
    }
}
