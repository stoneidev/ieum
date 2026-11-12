import Foundation
import Testing

@testable import CaptionCore

@Suite("Echo guard")
struct EchoGuardTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theOtherSidesWordsHeardAgainOnTheMicrophoneAreDropped() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("来週の月曜日からテストを始めてもいいですか", at: now)
        #expect(guardrail.isEcho("来週の月曜日からテストを始めてもいいですか", locale: "ko-KR", at: now.addingTimeInterval(1.5)))
        // a slightly different recognition of the same words is still the same sentence
        #expect(guardrail.isEcho("来週の月曜日からテストを始めても良いですか", locale: "ko-KR", at: now.addingTimeInterval(2)))
    }

    @Test func textInTheWrongLanguageIsDroppedWithoutAReference() {
        let guardrail = EchoGuard()
        #expect(guardrail.isEcho("来週の月曜日からテストを始めてもいいですか", locale: "ko-KR", at: now))
        #expect(!guardrail.isEcho("다음 주 월요일부터 테스트를 시작해도 될까요", locale: "ko-KR", at: now))
    }

    @Test func myOwnSentencesStay() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("来週の月曜日からテストを始めてもいいですか", at: now)
        #expect(!guardrail.isEcho("네, 괜찮습니다. 환경은 금요일까지 준비하겠습니다.", locale: "ko-KR", at: now.addingTimeInterval(3)))
    }

    @Test func aSharedPhraseDoesNotMakeADifferentSentenceAnEcho() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday", at: now)
        #expect(!guardrail.isEcho("Yes, we can ship it once QA signs off", locale: "en-US", at: now.addingTimeInterval(2)))
    }

    @Test func oldSentencesAreForgotten() {
        var guardrail = EchoGuard()
        guardrail.noteTheirs("Can we ship the beta on Thursday", at: now)
        #expect(!guardrail.isEcho("Can we ship the beta on Thursday", locale: "en-US", at: now.addingTimeInterval(40)))
    }

    @Test func veryShortResultsAreNotJudged() {
        let guardrail = EchoGuard()
        #expect(!guardrail.isEcho("네", locale: "ko-KR", at: now))
        #expect(guardrail.isEcho("  ", locale: "ko-KR", at: now))
    }
}
