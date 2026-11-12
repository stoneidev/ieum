import Foundation
import Testing

@testable import CaptionCore

private final class IdleCapture: AudioCapture, @unchecked Sendable {
    func start() async throws -> AsyncStream<AudioChunk> { AsyncStream { $0.finish() } }
    func stop() async {}
}

private final class FakeEngine: TranscriberEngine, @unchecked Sendable {
    let name = "fake"
    private let lock = NSLock()
    private var _stopped = false
    var stopped: Bool { lock.withLock { _stopped } }
    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func stop() async { lock.withLock { _stopped = true } }
}

@Suite("Call engine")
struct CallEngineTests {
    private func final(_ text: String, _ locale: String, at seconds: Double = 0) -> TranscriptionEvent {
        TranscriptionEvent(text: text, isFinal: true, locale: locale, timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    /// Engines that replay fixed events per locale.
    private func engine(_ script: [String: [TranscriptionEvent]], engines: [String: FakeEngine]) -> CallEngine {
        CallEngine(theirLocale: "ja-JP", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, _, _ in
            let fake = engines[locale] ?? FakeEngine()
            let events = script[locale] ?? []
            return (fake, AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            })
        }
    }

    private func collect(_ stream: AsyncThrowingStream<TranscriptionEvent, Error>) async throws -> [TranscriptionEvent] {
        var out: [TranscriptionEvent] = []
        for try await event in stream { out.append(event) }
        return out
    }

    @Test func eachSideIsTaggedWithItsSpeaker() async throws {
        let call = engine([
            "ja-JP": [final("来週の月曜日からテストを始めてもいいですか", "ja-JP")],
            "ko-KR": [final("네, 괜찮습니다. 환경은 금요일까지 준비하겠습니다.", "ko-KR", at: 3)],
        ], engines: [:])
        let events = try await collect(try await call.events(from: IdleCapture()))
        #expect(events.count == 2)
        #expect(events.first { $0.locale == "ja-JP" }?.speaker == .them)
        #expect(events.first { $0.locale == "ko-KR" }?.speaker == .me)
    }

    @Test func theMicrophoneHearingTheOtherSideIsNotShownAsMine() async throws {
        let call = engine([
            "ja-JP": [final("来週の月曜日からテストを始めてもいいですか", "ja-JP")],
            // the leak, recognized in Korean as nonsense, and again in the other side's own words
            "ko-KR": [final("らいしゅうのげつようびからてすとを", "ko-KR", at: 1), final("来週の月曜日からテストを始めてもいいですか", "ko-KR", at: 2)],
        ], engines: [:])
        let events = try await collect(try await call.events(from: IdleCapture()))
        #expect(events.map(\.speaker) == [.them])
    }

    @Test func stoppingStopsBothEngines() async throws {
        let them = FakeEngine(), me = FakeEngine()
        let call = engine([:], engines: ["ja-JP": them, "ko-KR": me])
        _ = try await call.events(from: IdleCapture())
        await call.stop()
        #expect(them.stopped && me.stopped)
    }

    @Test func aMicrophoneThatCannotStartStopsTheOtherSideToo() async {
        let them = FakeEngine()
        let call = CallEngine(theirLocale: "ja-JP", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, _, _ in
            if locale == "ko-KR" { throw EngineError.permissionDenied("Microphone access is blocked.") }
            return (them, AsyncThrowingStream { $0.finish() })
        }
        await #expect(throws: EngineError.self) { _ = try await call.events(from: IdleCapture()) }
        #expect(them.stopped)
    }

    @Test func englishSidesDoNotCloseSentencesAtPauses() async throws {
        let seen = Seen()
        let call = CallEngine(theirLocale: "en-US", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, options, _ in
            seen.add(locale, options.pauseFinalization)
            return (FakeEngine(), AsyncThrowingStream { $0.finish() })
        }
        _ = try await call.events(from: IdleCapture())
        #expect(seen.value("en-US") == .some(nil))
        #expect(seen.value("ko-KR") == .some(0.7))
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: TimeInterval?] = [:]
        func add(_ locale: String, _ pause: TimeInterval?) { lock.withLock { map[locale] = pause } }
        func value(_ locale: String) -> TimeInterval?? { lock.withLock { map[locale] } }
    }
}
