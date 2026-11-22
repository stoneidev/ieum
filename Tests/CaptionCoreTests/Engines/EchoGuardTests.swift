import Foundation
import Testing

@testable import CaptionCore

@Suite("Echo guard")
struct EchoGuardTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theOtherSidesWordsHeardAgainOnTheMicrophoneAreDropped() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("来週の月曜日からテストを始めてもいいですか", at: now)
        #expect(guardrail.isEcho("来週の月曜日からテストを始めてもいいですか", at: now.addingTimeInterval(1.5)))
        // a slightly different recognition of the same words is still the same sentence
        #expect(guardrail.isEcho("来週の月曜日からテストを始めても良いですか", at: now.addingTimeInterval(2)))
    }

    @Test func withoutAReferenceNothingIsAnEcho() {
        let guardrail = EchoGuard()
        #expect(!guardrail.isEcho("来週の月曜日からテストを始めてもいいですか", at: now))
        #expect(!guardrail.isEcho("다음 주 월요일부터 테스트를 시작해도 될까요", at: now))
    }

    @Test func myOwnSentencesStay() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("来週の月曜日からテストを始めてもいいですか", at: now)
        #expect(!guardrail.isEcho("네, 괜찮습니다. 환경은 금요일까지 준비하겠습니다.", at: now.addingTimeInterval(3)))
    }

    @Test func aSharedPhraseDoesNotMakeADifferentSentenceAnEcho() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday", at: now)
        #expect(!guardrail.isEcho("Yes, we can ship it once QA signs off", at: now.addingTimeInterval(2)))
    }

    @Test func oldSentencesAreForgotten() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday", at: now)
        #expect(!guardrail.isEcho("Can we ship the beta on Thursday", at: now.addingTimeInterval(40)))
    }

    @Test func veryShortResultsAreNotJudged() {
        let guardrail = EchoGuard()
        #expect(!guardrail.isEcho("네", at: now))
        #expect(guardrail.isEcho("  ", at: now))
    }
}

@Suite("Echo guard: real speech stays")
struct EchoGuardKeepsSpeechTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func aShortAnswerThatRepeatsTheirWordIsKept() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday", at: now)
        #expect(!guardrail.isEcho("Thursday", at: now.addingTimeInterval(1)))
        #expect(!guardrail.isEcho("ship the beta", at: now.addingTimeInterval(1)))
        #expect(!guardrail.isEcho("금요일이요", at: now.addingTimeInterval(1)))
    }

    @Test func aLongSentenceInTheSameLanguageThatCopiesTheirsIsAnEcho() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday if QA is done", at: now)
        #expect(guardrail.isEcho("can we ship the beta on thursday if QA is done", at: now.addingTimeInterval(1.2)))
    }

    @Test func koreanWithEnglishTermsIsNotMistakenForNoise() {
        let guardrail = EchoGuard()
        #expect(!guardrail.isEcho("staging deploy merge main 했어요", at: now))
    }
}
