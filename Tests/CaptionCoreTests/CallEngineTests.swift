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
    /// `delays` holds back a side's events, as in a real call where the echo of the other side arrives after the other side.
    private func engine(_ script: [String: [TranscriptionEvent]], engines: [String: FakeEngine], delays: [String: Duration] = [:]) -> CallEngine {
        CallEngine(theirLocale: "ja-JP", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, _, _ in
            let fake = engines[locale] ?? FakeEngine()
            let events = script[locale] ?? []
            let delay = delays[locale]
            return (fake, AsyncThrowingStream { continuation in
                Task {
                    if let delay { try? await Task.sleep(for: delay) }
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                }
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
            // the leak recognized again in the other side's own words (same language on both sides)
            "ko-KR": [final("来週の月曜日からテストを始めてもいいですか", "ko-KR", at: 2)],
        ], engines: [:], delays: ["ko-KR": .milliseconds(150)])
        let events = try await collect(try await call.events(from: IdleCapture()))
        #expect(events.filter { !$0.text.isEmpty }.map(\.speaker) == [.them])
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

    @Test func whenOneSideEndsTheWholeCallEnds() async throws {
        // The other side (system audio) stops delivering while the microphone would go on forever.
        let call = CallEngine(theirLocale: "ja-JP", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, _, _ in
            if locale == "ja-JP" { return (FakeEngine(), AsyncThrowingStream { $0.finish() }) }
            return (FakeEngine(), AsyncThrowingStream { _ in })   // never yields, never finishes
        }
        let stream = try await call.events(from: IdleCapture())
        let events = try await withThrowingTaskGroup(of: [TranscriptionEvent].self) { group in
            group.addTask { try await self.collect(stream) }
            group.addTask { try await Task.sleep(for: .seconds(3)); throw EngineError.captureFailed("the call did not end") }
            let first = try await group.next() ?? []
            group.cancelAll()
            return first
        }
        #expect(events.isEmpty)
    }

    @Test func aFailureOnOneSideEndsTheCallWithThatError() async {
        let call = CallEngine(theirLocale: "ja-JP", myLocale: "ko-KR", options: EngineOptions(), microphone: IdleCapture()) { locale, _, _ in
            if locale == "ko-KR" { return (FakeEngine(), AsyncThrowingStream { $0.finish(throwing: EngineError.captureFailed("microphone unplugged")) }) }
            return (FakeEngine(), AsyncThrowingStream { _ in })
        }
        do {
            _ = try await collect(try await call.events(from: IdleCapture()))
            Issue.record("the call should have failed")
        } catch let error as EngineError {
            #expect(error.localizedDescription == "microphone unplugged")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func aDroppedMicrophoneEchoStillEndsTheLineOnScreen() async throws {
        let call = engine([
            "ja-JP": [final("来週の月曜日からテストを始めてもいいですか", "ja-JP")],
            "ko-KR": [final("来週の月曜日からテストを始めてもいいですか", "ko-KR", at: 1)],
        ], engines: [:])
        let events = try await collect(try await call.events(from: IdleCapture()))
        let mine = events.filter { $0.speaker == .me }
        #expect(mine.count == 1 && mine[0].text.isEmpty && mine[0].isFinal)
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
