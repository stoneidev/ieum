import Foundation
import Testing

@testable import IeumCore

private func event(_ text: String, final: Bool, confidence: Double?, range: ClosedRange<Double>? = nil, locale: String) -> TranscriptionEvent {
    TranscriptionEvent(text: text, isFinal: final, locale: locale, audioStart: range?.lowerBound, audioEnd: range?.upperBound, confidence: confidence)
}

private let en = "en-US", ko = "ko-KR"
private let goodEnglish = "Thanks for joining the call. Today we will review the quarterly budget."
private let gibberish = "Thanks for joining the cal today we wl re l t t pe e e"
private let goodKorean = "안녕하세요 오늘 회의에서는 분기별 예산을 검토하겠습니다."

@Suite("Language plausibility")
struct PlausibilityTests {
    @Test func realTextMatchesItsOwnLanguage() {
        #expect(LanguageArbiter.textPlausibility(text: goodEnglish, locale: en) > 0.8)
        #expect(LanguageArbiter.textPlausibility(text: goodKorean, locale: ko) > 0.8)
    }

    @Test func textInTheOtherLanguageScoresLow() {
        #expect(LanguageArbiter.textPlausibility(text: goodEnglish, locale: ko) < 0.2)
        #expect(LanguageArbiter.textPlausibility(text: goodKorean, locale: en) < 0.2)
    }

    @Test func latinGibberishFromTheKoreanRecognizerIsNotKorean() {
        #expect(LanguageArbiter.textPlausibility(text: gibberish, locale: ko) < 0.2)
    }

    @Test func technicalTermsInsideKoreanStillCountAsKorean() {
        #expect(LanguageArbiter.textPlausibility(text: "쿠버네티스 클러스터에 Terraform 배포를 했습니다", locale: ko) > 0.5)
    }
}

@Suite("Language arbiter")
struct LanguageArbiterTests {
    private func arbiter() -> LanguageArbiter { LanguageArbiter(locales: [en, ko]) }

    @Test func englishSpeechKeepsTheEnglishFinalAndDropsTheNonsense() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        shown += a.ingest(event(gibberish, final: true, confidence: 0.59, range: 0...4, locale: ko), from: ko, now: 5.0)
        shown += a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...4, locale: en), from: en, now: 5.2)
        shown += a.flush(now: 9)
        #expect(shown.map(\.text) == [goodEnglish])
    }

    @Test func aSureFinalIsShownAtOnceWhenTheOtherRecognizerOfferedNothing() {
        var a = arbiter()
        #expect(a.ingest(event(goodKorean, final: true, confidence: 0.98, range: 0...4, locale: ko), from: ko, now: 5.0).map(\.text) == [goodKorean])
        #expect(a.finish().isEmpty)
    }

    @Test func koreanSpeechWhereEnglishReturnsNothingIsShownAfterTheHoldWhenNotSoSure() {
        var a = arbiter()
        #expect(a.ingest(event(goodKorean, final: true, confidence: 0.85, range: 0...4, locale: ko), from: ko, now: 5.0).isEmpty)
        #expect(a.flush(now: 5.3).isEmpty)
        #expect(a.flush(now: 5.8).map(\.text) == [goodKorean])
    }

    @Test func aSureFinalStillWaitsWhenTheOtherRecognizerWasOfferingSomethingCredible() {
        var a = arbiter()
        _ = a.ingest(event("Thanks for joining the call", final: false, confidence: 0.95, locale: en), from: en, now: 3)
        // The Korean recognizer's final is sure, but English was credibly in progress: wait for the English final.
        #expect(a.ingest(event(goodKorean, final: true, confidence: 0.98, range: 0...4, locale: ko), from: ko, now: 5.0).isEmpty)
        let shown = a.ingest(event(goodEnglish, final: true, confidence: 0.99, range: 0...4, locale: en), from: en, now: 5.2)
        #expect(shown.map(\.text) == [goodKorean] || shown.map(\.text) == [goodEnglish])
        #expect(shown.count == 1)
    }

    @Test func aWeakFinalWaitsLongerSoABetterRivalCanStillWin() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        // English noise over Korean speech (weak score) arrives first ...
        shown += a.ingest(event("Okay, you.", final: true, confidence: 0.75, range: 12...14.7, locale: en), from: en, now: 15.9)
        shown += a.flush(now: 16.8)            // a confident final would be out by now
        #expect(shown.isEmpty)
        // ... the Korean recognizer answers 1.4 s later and wins; the noise is never shown.
        shown += a.ingest(event(goodKorean, final: true, confidence: 0.98, range: 12...16.9, locale: ko), from: ko, now: 17.3)
        shown += a.finish()
        #expect(shown.map(\.text) == [goodKorean])
    }

    @Test func aConfidentFinalIsNotHeldLonger() {
        var a = arbiter()
        #expect(a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...4, locale: en), from: en, now: 5).map(\.text) == [goodEnglish])
    }

    @Test func aDueSentenceNeverOvertakesAnEarlierOneThatIsStillWaiting() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        // Earlier sentence: weak score, so it waits for a possible rival ...
        shown += a.ingest(event("..., that works for me.", final: true, confidence: 0.7, range: 8...10.2, locale: en), from: en, now: 12.0)
        // ... a later sentence is sure and would be shown at once, but must stay behind the earlier one.
        shown += a.ingest(event("What about the budget? I would like an answer today.", final: true, confidence: 0.97, range: 10.2...11.6, locale: en), from: en, now: 12.1)
        #expect(shown.isEmpty)
        shown += a.flush(now: 14.0)
        #expect(shown.map(\.text) == ["..., that works for me.", "What about the budget? I would like an answer today."])
    }

    @Test func aLoneNonsenseFinalIsDropped() {
        var a = arbiter()
        _ = a.ingest(event(gibberish, final: true, confidence: 0.59, range: 0...4, locale: ko), from: ko, now: 5)
        #expect(a.flush(now: 9).isEmpty)
    }

    @Test func nothingIsEmittedTwice() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        shown += a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...4, locale: en), from: en, now: 5)
        shown += a.ingest(event(gibberish, final: true, confidence: 0.59, range: 0...4, locale: ko), from: ko, now: 5.1)
        shown += a.flush(now: 20)
        shown += a.finish()
        #expect(shown.count == 1)
    }

    @Test func aLateRivalForSpeechThatWasAlreadyShownIsDropped() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        // The English result is shown on its own after the hold ...
        shown += a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...4, locale: en), from: en, now: 5)
        shown += a.flush(now: 6)
        // ... then the Korean recognizer finally answers with a Hangul transliteration of the same speech.
        shown += a.ingest(event("땡스 포 조이닝 더 콜 투데이 위 윌 리뷰 더 쿼털리 버짓", final: true, confidence: 0.9, range: 0...4, locale: ko), from: ko, now: 6.5)
        shown += a.finish()
        #expect(shown.map(\.text) == [goodEnglish])
    }

    @Test func aBetterLateResultIsNotMistakenForADuplicateOfEarlierNoise() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        // The English recognizer's noise over Korean speech is shown first (it scrapes past the solo threshold) ...
        shown += a.ingest(event("Okay, you.", final: true, confidence: 0.75, range: 12...14.7, locale: en), from: en, now: 15.9)
        shown += a.flush(now: 16.8)
        // ... then the Korean recognizer delivers the real sentence for the same stretch. It must still appear.
        shown += a.ingest(event(goodKorean, final: true, confidence: 0.98, range: 12...16.9, locale: ko), from: ko, now: 17.3)
        shown += a.finish()
        #expect(shown.map(\.text).contains(goodKorean))
    }

    @Test func separateSentencesInDifferentLanguagesAreBothKept() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        shown += a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...3, locale: en), from: en, now: 3.4)
        shown += a.ingest(event(goodKorean, final: true, confidence: 0.92, range: 5...8, locale: ko), from: ko, now: 8.4)
        shown += a.finish()
        #expect(shown.map(\.text) == [goodEnglish, goodKorean])
    }

    @Test func interimsOfTheLeaderAreShownAndTheOtherIsHidden() {
        var a = arbiter()
        let first = a.ingest(event("Thanks for joining", final: false, confidence: 0.95, locale: en), from: en, now: 1)
        #expect(first.map(\.text) == ["Thanks for joining"])
        let hidden = a.ingest(event("thanks for join", final: false, confidence: 0.5, locale: ko), from: ko, now: 1.1)
        #expect(hidden.isEmpty)
    }

    @Test func theDisplayFollowsTheLanguageThatBecomesMuchBetter() {
        var a = arbiter()
        // The Korean recognizer's nonsense leads at first (English recognizer still silent) ...
        let early = a.ingest(event("thanks for joining the cal", final: false, confidence: 0.4, locale: ko), from: ko, now: 1)
        #expect(early.count == 1)
        // ... then the English recognizer produces real text with high confidence and takes over.
        let switched = a.ingest(event("Thanks for joining the call", final: false, confidence: 0.95, locale: en), from: en, now: 1.3)
        #expect(switched.map(\.text) == ["Thanks for joining the call"])
        // The Korean recognizer no longer shows through.
        #expect(a.ingest(event("thanks for joining the cal today", final: false, confidence: 0.4, locale: ko), from: ko, now: 1.5).isEmpty)
    }

    @Test func aNewUtteranceStartsFresh() {
        var a = arbiter()
        _ = a.ingest(event("Thanks for joining", final: false, confidence: 0.95, locale: en), from: en, now: 1)
        _ = a.ingest(event(goodEnglish, final: true, confidence: 0.97, range: 0...3, locale: en), from: en, now: 3.5)
        _ = a.flush(now: 5)
        let next = a.ingest(event("안녕하세요 오늘", final: false, confidence: 0.9, locale: ko), from: ko, now: 8)
        #expect(next.map(\.text) == ["안녕하세요 오늘"])
    }

    @Test func missingConfidenceFallsBackToAnAssumedValue() {
        var a = arbiter()
        var shown: [TranscriptionEvent] = []
        shown += a.ingest(event(goodEnglish, final: true, confidence: nil, range: 0...3, locale: en), from: en, now: 3)
        shown += a.finish()
        #expect(shown.map(\.text) == [goodEnglish])
    }

    @Test func emptyEventsAreIgnored() {
        var a = arbiter()
        #expect(a.ingest(event("  ", final: false, confidence: 0.9, locale: en), from: en, now: 1).isEmpty)
        #expect(a.finish().isEmpty)
    }
}
