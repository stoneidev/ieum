import Foundation
import Testing

@testable import CaptionCore

private func event(_ text: String, final: Bool = false) -> TranscriptionEvent {
    TranscriptionEvent(text: text, isFinal: final, locale: "en-US")
}

@Suite("Early words")
struct PreviewingEngineTests {
    @Test func skipsTheSentencesTheModernRecognizerAlreadyFinished() {
        // "Thanks for joining the call" is 23 letters.
        #expect(PreviewingEngine.Gate.dropping(letters: 23, from: "Thanks for joining the call today we will") == "today we will")
        // Word splitting differs between recognizers: "road map" and "roadmap" have the same letters.
        #expect(PreviewingEngine.Gate.dropping(letters: 7, from: "road map please open") == "please open")
        #expect(PreviewingEngine.Gate.dropping(letters: 0, from: " hello ") == "hello")
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
}
