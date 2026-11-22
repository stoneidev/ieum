import Foundation
import Testing

@testable import CaptionCore

private func event(_ text: String, final: Bool = false, locale: String = "en-US") -> TranscriptionEvent {
    TranscriptionEvent(text: text, isFinal: final, locale: locale)
}

@Suite("Early words")
struct PreviewingEngineTests {
    @Test func skipsTheSentencesTheModernRecognizerAlreadyFinished() {
        // "Thanks for joining the call" is 23 letters.
        #expect(PreviewingEngine.Gate.dropping(letters: 23, from: "Thanks for joining the call today we will") == "today we will")
        // Word splitting differs between recognizers: "road map" and "roadmap" have the same letters.
        #expect(PreviewingEngine.Gate.dropping(letters: 7, from: "road map please open") == "please open")
        #expect(PreviewingEngine.Gate.dropping(letters: 0, from: " hello ") == "hello")
        // Japanese and Chinese have no spaces: the cut falls between characters.
        #expect(PreviewingEngine.Gate.dropping(letters: 6, from: "来週の月曜日から始めます") == "から始めます")
        #expect(PreviewingEngine.Gate.dropping(letters: 5, from: "预算已确认。明天开始") == "明天开始")
        #expect(PreviewingEngine.Gate.dropping(letters: 20, from: "来週の月曜日から始めます") == "")
    }

    @Test func showsNothingWhileTheLegacyTextHasNotReachedTheNewSentence() {
        #expect(PreviewingEngine.Gate.dropping(letters: 23, from: "Thanks for joining the call") == "")
        #expect(PreviewingEngine.Gate.dropping(letters: 23, from: "Thanks for joining") == "")
    }

    @Test func earlyWordsReplaceModernInterimsOnceTheyExist() {
        var gate = PreviewingEngine.Gate()
        let r1 = gate.primary(event("Thanks"))
        #expect(r1)                       // nothing early yet: modern words show
        let r2 = gate.preview(event("Thanks"))
        #expect(r2?.text == "Thanks")
        let r3 = gate.primary(event("Thanks for"))
        #expect(!r3)                  // early words exist: modern interims are hidden
        let r4 = gate.preview(event("Thanks for joining the call"))
        #expect(r4?.text == "Thanks for joining the call")
        let r5 = gate.primary(event("Thanks for joining the call.", final: true))
        #expect(r5)   // finals always pass
    }

    @Test func nextSentenceInTheSameLegacySessionShowsOnlyItsOwnWords() {
        var gate = PreviewingEngine.Gate()
        _ = gate.preview(event("Thanks for joining the call"))
        _ = gate.primary(event("Thanks for joining the call.", final: true))
        let r6 = gate.preview(event("Thanks for joining the call today"))
        #expect(r6?.text == "today")
        let r7 = gate.preview(event("Thanks for joining the call today we will"))
        #expect(r7?.text == "today we will")
    }

    @Test func modernInterimsShowWhileTheLegacyTextCatchesUp() {
        var gate = PreviewingEngine.Gate()
        _ = gate.preview(event("Thanks for joining the call"))
        _ = gate.primary(event("Thanks for joining the call.", final: true))
        let r8 = gate.preview(event("Thanks for joining the call"))
        #expect(r8 == nil)
        let r9 = gate.primary(event("Today we"))
        #expect(r9)
    }

    @Test func aLegacyPauseStartsAFreshSession() {
        var gate = PreviewingEngine.Gate()
        _ = gate.preview(event("Hello there"))
        _ = gate.primary(event("Hello there.", final: true))
        let r10 = gate.preview(event("Hello there", final: true))
        #expect(r10 == nil)   // the legacy session ended
        let r11 = gate.preview(event("Please open"))
        #expect(r11?.text == "Please open")
    }

    @Test func modernInterimsComeBackWhenTheLegacyRecognizerIsGone() {
        var gate = PreviewingEngine.Gate()
        _ = gate.preview(event("Hello"))
        gate.lostPreview()
        let r12 = gate.primary(event("Hello there"))
        #expect(r12)
        let r13 = gate.preview(event("Hello there"))
        #expect(r13 == nil)
    }

    @Test func modernFinalBeforeFirstPreviewWordIsSkippedFromLatePreview() {
        // Modern finishes "Hello." before legacy has said anything; the delayed cumulative
        // preview must not re-show that sentence as an interim.
        var gate = PreviewingEngine.Gate()
        _ = gate.primary(event("Hello.", final: true))
        let shown = gate.preview(event("Hello there"))
        #expect(shown?.text == "there")
    }

    @Test func wrongLanguageFinalDoesNotStripEarlyWords() {
        // Conversation mode: Korean modern may finalize Hangul while the English preview is live.
        var gate = PreviewingEngine.Gate()
        _ = gate.preview(event("Thanks for joining"))
        _ = gate.primary(event("생큐포조이닝", final: true, locale: "ko-KR"))
        let shown = gate.preview(event("Thanks for joining the call"))
        #expect(shown?.text == "Thanks for joining the call")
    }

    @Test func wrongLanguagePendingFinalDoesNotStripFirstPreviewWords() {
        var gate = PreviewingEngine.Gate()
        _ = gate.primary(event("생큐포조이닝", final: true, locale: "ko-KR"))
        let shown = gate.preview(event("Thanks for joining"))
        #expect(shown?.text == "Thanks for joining")
    }

    @Test func wrapIfNeededIsANoOpWhenEarlyWordsAreOffOrPreviewIsMissing() async {
        let fake = PassthroughEngine(name: "primary")
        var options = EngineOptions()
        options.showsWordsSooner = false
        let kept = await PreviewingEngine.wrapIfNeeded(
            primary: fake, localeID: "en-US", options: options
        ) { _, _ in PassthroughEngine(name: "preview") }
        #expect((kept as? PassthroughEngine) === fake)

        options.showsWordsSooner = true
        let withoutPreview = await PreviewingEngine.wrapIfNeeded(
            primary: fake, localeID: "ja-JP", options: options
        ) { _, _ in nil }
        #expect((withoutPreview as? PassthroughEngine) === fake)
    }

    @Test func wrapIfNeededAddsEarlyWordsWhenEnabledAndPreviewExists() async throws {
        let fake = PassthroughEngine(name: "primary")
        let preview = PassthroughEngine(name: "preview")
        var options = EngineOptions()
        options.showsWordsSooner = true
        let wrapped = await PreviewingEngine.wrapIfNeeded(
            primary: fake, localeID: "en-US", options: options
        ) { _, _ in preview }
        let engine = try #require(wrapped as? PreviewingEngine)
        #expect(engine.name == "primary + early words")
        #expect(engine.isPreview(preview))
        #expect(!engine.isPreview(fake))
    }
}

private final class PassthroughEngine: TranscriberEngine, @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}
