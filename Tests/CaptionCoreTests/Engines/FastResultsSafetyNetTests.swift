import Foundation
import Testing

@testable import CaptionCore

@Suite("Fast-results tail guard")
struct FastResultsTailGuardTests {
    @Test func appliesOnlyToKoreanLocales() {
        #expect(FastResultsTailGuard.applies(to: "ko-KR"))
        #expect(FastResultsTailGuard.applies(to: "ko"))
        #expect(!FastResultsTailGuard.applies(to: "en-US"))
        #expect(!FastResultsTailGuard.applies(to: "ja-JP"))
        #expect(!FastResultsTailGuard.applies(to: "zh-CN"))
    }

    @Test func holdsWhenSpeechContinuesPastTheFinal() {
        #expect(FastResultsTailGuard.shouldHoldFinal(audioEnd: 12.5, lastSpeechAt: 15.0))
        #expect(FastResultsTailGuard.shouldHoldFinal(audioEnd: 12.5, lastSpeechAt: 12.5 + FastResultsTailGuard.speechPastFinal + 0.01))
        #expect(!FastResultsTailGuard.shouldHoldFinal(audioEnd: 12.5, lastSpeechAt: 12.6))
        #expect(!FastResultsTailGuard.shouldHoldFinal(audioEnd: nil, lastSpeechAt: 15.0))
    }

    @Test func prefersALongerOverlappingSlowFinal() {
        #expect(FastResultsTailGuard.prefersSlow(
            fastText: "쿠버네티스 클러스터를",
            slowText: "쿠버네티스 클러스터를 점검하고 배포합니다",
            fastRange: (0, 12.5),
            slowRange: (0, 15.0)
        ))
        #expect(!FastResultsTailGuard.prefersSlow(
            fastText: "짧은",
            slowText: "긴 문장이지만 다른 구간",
            fastRange: (0, 5),
            slowRange: (10, 15)
        ))
        #expect(FastResultsTailGuard.prefersSlow(
            fastText: "짧",
            slowText: "더 긴 문장",
            fastRange: nil,
            slowRange: nil
        ))
    }
}

@Suite("Fast-results safety net gate")
struct FastResultsSafetyNetGateTests {
    private func final(_ text: String, start: Double, end: Double) -> TranscriptionEvent {
        TranscriptionEvent(text: text, isFinal: true, locale: "ko-KR", audioStart: start, audioEnd: end)
    }

    private func interim(_ text: String, start: Double, end: Double) -> TranscriptionEvent {
        TranscriptionEvent(text: text, isFinal: false, locale: "ko-KR", audioStart: start, audioEnd: end)
    }

    @Test func completeFastFinalsPassThrough() {
        var gate = FastResultsSafetyNet.Gate()
        let out = gate.fast(final("안녕하세요.", start: 0, end: 1.2), lastSpeechAt: 1.25)
        #expect(out.count == 1 && out[0].isFinal && out[0].text == "안녕하세요.")
        #expect(gate.pending == nil)
    }

    @Test func truncatedFastFinalIsHeldAsInterimUntilSlowRecovers() {
        var gate = FastResultsSafetyNet.Gate()
        let held = gate.fast(final("쿠버네티스 클러스터를", start: 0, end: 12.5), lastSpeechAt: 15.0)
        #expect(held.count == 1 && !held[0].isFinal)
        #expect(gate.pending?.text == "쿠버네티스 클러스터를")

        let recovered = gate.slow(final("쿠버네티스 클러스터를 점검하고 슬랙에 올립니다", start: 0, end: 15.0))
        #expect(recovered?.isFinal == true)
        #expect(recovered?.text == "쿠버네티스 클러스터를 점검하고 슬랙에 올립니다")
        #expect(gate.pending == nil)
    }

    @Test func interimsPassWhileHolding() {
        var gate = FastResultsSafetyNet.Gate()
        let shown = gate.fast(interim("안녕하세요", start: 0, end: 0.8), lastSpeechAt: 0.8)
        #expect(shown.count == 1 && !shown[0].isFinal)
    }

    @Test func flushCommitsAHeldFinalWhenTheSessionEnds() {
        var gate = FastResultsSafetyNet.Gate()
        _ = gate.fast(final("잘린 문장", start: 0, end: 5), lastSpeechAt: 8)
        let flushed = gate.flush()
        #expect(flushed?.isFinal == true && flushed?.text == "잘린 문장")
        #expect(gate.pending == nil)
    }

    @Test func aNewFastFinalFlushesThePreviousHeldOne() {
        var gate = FastResultsSafetyNet.Gate()
        _ = gate.fast(final("첫 문장", start: 0, end: 5), lastSpeechAt: 8)
        let next = gate.fast(final("다음 문장.", start: 9, end: 11), lastSpeechAt: 11.1)
        #expect(next.count == 2)
        #expect(next[0].isFinal && next[0].text == "첫 문장")
        #expect(next[1].isFinal && next[1].text == "다음 문장.")
    }

    @Test func longerSlowFinalAfterACommitIsDroppedToAvoidDuplicates() {
        var gate = FastResultsSafetyNet.Gate()
        _ = gate.fast(final("짧은", start: 0, end: 2), lastSpeechAt: 2.1)
        let again = gate.slow(final("짧은 문장을 길게", start: 0, end: 3))
        #expect(again == nil)
    }
}

@Suite("Speech activity clock")
struct SpeechActivityClockTests {
    @Test func speechRaisesTheWatermark() {
        let clock = SpeechActivityClock()
        clock.ingest(levelDB: -10, duration: 0.5)
        #expect(clock.fedSeconds == 0.5)
        #expect(clock.lastSpeechAt == 0.5)
        clock.ingest(levelDB: -80, duration: 0.4)
        #expect(clock.fedSeconds == 0.9)
        #expect(clock.lastSpeechAt == 0.5)
    }

    @Test func wrapIfNeededIsANoOpWhenFastIsOffOrLocaleIsNotKorean() async throws {
        let fake = PassthroughEngine()
        let kept = try await FastResultsSafetyNet.wrapIfNeeded(
            primary: fake, localeID: "ko-KR", options: EngineOptions(fast: false)
        ) { PassthroughEngine() }
        #expect((kept as? PassthroughEngine) === fake)

        let english = try await FastResultsSafetyNet.wrapIfNeeded(
            primary: fake, localeID: "en-US", options: EngineOptions(fast: true)
        ) { PassthroughEngine() }
        #expect((english as? PassthroughEngine) === fake)
    }

    @Test func wrapIfNeededAddsTheSafetyNetForKoreanFastSessions() async throws {
        let fake = PassthroughEngine()
        let wrapped = try await FastResultsSafetyNet.wrapIfNeeded(
            primary: fake, localeID: "ko-KR", options: EngineOptions(fast: true)
        ) { PassthroughEngine() }
        #expect(wrapped is FastResultsSafetyNet)
    }
}

private final class PassthroughEngine: TranscriberEngine, @unchecked Sendable {
    let name = "passthrough"
    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}
