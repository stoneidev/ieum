import Foundation

/// Fast words on screen, complete finals when `.fastResults` would have dropped the tail.
///
/// Runs two modern engines on the same audio: one with fast results (interim words) and one without (accurate
/// finals). A fast final that ends while speech is still being heard is held and shown as interim until the slow
/// engine delivers the full sentence — the recovery measured in `Benchmarks/research/dual.swift` (`two` mode).
public final class FastResultsSafetyNet: TranscriberEngine, @unchecked Sendable {
    public var name: String { "\(fast.name) + complete finals" }

    private let fast: any TranscriberEngine
    private let slow: any TranscriberEngine
    private let clock: SpeechActivityClock
    private let lock = NSLock()
    private var engines: [any TranscriberEngine] = []

    public init(fast: any TranscriberEngine, slow: any TranscriberEngine, clock: SpeechActivityClock = SpeechActivityClock()) {
        self.fast = fast
        self.slow = slow
        self.clock = clock
    }

    /// Off until the hold gate catches the measured truncation: on `codeswitch-ko` the fast final reports
    /// `audioEnd` at the end of the audio although its text stops early, so nothing is held (CER 47 % → 48–50 %)
    /// while the second analyzer doubles CPU (docs/BENCHMARKS.md, "Fast-results tail safety net").
    static let isEnabled = false

    /// Wraps `primary` with a non-fast twin when the locale needs the safety net and fast results are on.
    public static func wrapIfNeeded(
        primary: any TranscriberEngine,
        localeID: String,
        options: EngineOptions,
        makeSlow: () async throws -> (any TranscriberEngine)?
    ) async throws -> any TranscriberEngine {
        guard isEnabled, options.fast, FastResultsTailGuard.applies(to: localeID) else { return primary }
        guard let slow = try await makeSlow() else { return primary }
        return FastResultsSafetyNet(fast: primary, slow: slow)
    }

    public func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        let clock = self.clock
        let tracked = TrackingCapture(capture, clock: clock)
        let shared = SharedAudioCapture(source: tracked, branchCount: 2)
        let branches = shared.branches
        let fast = self.fast
        let slow = self.slow
        let streams: (AsyncThrowingStream<TranscriptionEvent, Error>, AsyncThrowingStream<TranscriptionEvent, Error>)
        do {
            streams = try await withThrowingTaskGroup(of: (Int, AsyncThrowingStream<TranscriptionEvent, Error>).self) { group in
                group.addTask { (0, try await fast.events(from: branches[0])) }
                group.addTask { (1, try await slow.events(from: branches[1])) }
                var ordered = [AsyncThrowingStream<TranscriptionEvent, Error>?](repeating: nil, count: 2)
                do {
                    for try await (index, stream) in group { ordered[index] = stream }
                } catch {
                    shared.abort(error)
                    throw error
                }
                return (ordered[0]!, ordered[1]!)
            }
        } catch {
            await fast.stop()
            await slow.stop()
            throw error
        }
        lock.withLock { engines = [fast, slow] }

        let merger = Merger(clock: clock)
        return AsyncThrowingStream { continuation in
            let driver = Task { await merger.run(fast: streams.0, slow: streams.1, into: continuation) }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }

    public func stop() async {
        let current = lock.withLock { engines }
        for engine in current { await engine.stop() }
    }

    /// Holds truncated fast finals and prefers longer overlapping slow finals.
    struct Gate {
        private(set) var pending: TranscriptionEvent?
        private(set) var lastCommitted: TranscriptionEvent?

        mutating func fast(_ event: TranscriptionEvent, lastSpeechAt: Double) -> [TranscriptionEvent] {
            if event.isFinal {
                var out: [TranscriptionEvent] = []
                if let pending {
                    out.append(pending)
                    lastCommitted = pending
                    self.pending = nil
                }
                if FastResultsTailGuard.shouldHoldFinal(audioEnd: event.audioEnd, lastSpeechAt: lastSpeechAt) {
                    pending = event
                    out.append(TranscriptionEvent(
                        text: event.text, isFinal: false, locale: event.locale, timestamp: event.timestamp,
                        audioStart: event.audioStart, audioEnd: event.audioEnd, confidence: event.confidence,
                        speaker: event.speaker
                    ))
                } else {
                    lastCommitted = event
                    out.append(event)
                }
                return out
            }
            return [event]
        }

        mutating func slow(_ event: TranscriptionEvent) -> TranscriptionEvent? {
            guard event.isFinal else { return nil }
            if let pending {
                // Held because speech continued: take the slow final when it is at least as long (usual recovery
                // is strictly longer; equal length still confirms the sentence so the transcript can close).
                guard FastResultsTailGuard.letterCount(event.text) >= FastResultsTailGuard.letterCount(pending.text) else {
                    return nil
                }
                if let pendingRange = FastResultsTailGuard.range(of: pending),
                   let slowRange = FastResultsTailGuard.range(of: event),
                   !FastResultsTailGuard.rangesOverlap(pendingRange, slowRange) {
                    return nil
                }
                self.pending = nil
                lastCommitted = event
                return event
            }
            // Already committed a short final; a longer slow one would duplicate the line — drop it.
            return nil
        }

        /// Session ending: commit whatever was held so the transcript is not missing the last sentence.
        mutating func flush() -> TranscriptionEvent? {
            guard let pending else { return nil }
            self.pending = nil
            lastCommitted = pending
            return pending
        }
    }

    private actor Merger {
        private var gate = Gate()
        private let clock: SpeechActivityClock
        private var continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?
        private var finished = false
        private var remaining = 2

        init(clock: SpeechActivityClock) {
            self.clock = clock
        }

        func run(
            fast: AsyncThrowingStream<TranscriptionEvent, Error>,
            slow: AsyncThrowingStream<TranscriptionEvent, Error>,
            into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
        ) async {
            self.continuation = continuation
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [self] in
                    do {
                        for try await event in fast { await fromFast(event) }
                        await streamEnded()
                    } catch {
                        await finish(error)
                    }
                }
                group.addTask { [self] in
                    // Slow is a safety net: if it dies, flush any held fast final and keep going on fast alone.
                    do {
                        for try await event in slow { await fromSlow(event) }
                    } catch {
                        await flushPending()
                    }
                    await streamEnded()
                }
            }
        }

        private func fromFast(_ event: TranscriptionEvent) {
            guard !finished else { return }
            for item in gate.fast(event, lastSpeechAt: clock.lastSpeechAt) {
                continuation?.yield(item)
            }
        }

        private func fromSlow(_ event: TranscriptionEvent) {
            guard !finished else { return }
            if let shown = gate.slow(event) {
                continuation?.yield(shown)
            }
        }

        private func flushPending() {
            guard !finished else { return }
            if let flushed = gate.flush() {
                continuation?.yield(flushed)
            }
        }

        private func streamEnded() {
            guard !finished else { return }
            remaining -= 1
            if remaining > 0 { return }
            flushPending()
            finish(nil)
        }

        private func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        }
    }
}
