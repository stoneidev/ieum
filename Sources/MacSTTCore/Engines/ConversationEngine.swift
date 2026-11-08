import Foundation

/// Two-way conversation: one recognizer per language runs on the same audio and `LanguageArbiter` picks, for every
/// utterance, the language that was actually spoken. Needs the modern engine (macOS 26) for every language.
public final class ConversationEngine: TranscriberEngine, @unchecked Sendable {
    public var name: String { "Conversation (\(locales.joined(separator: " + ")))" }

    private let locales: [String]
    private let options: EngineOptions
    private let lock = NSLock()
    private var engines: [any TranscriberEngine] = []

    public init(locales: [String], options: EngineOptions) {
        self.locales = locales
        self.options = options
    }

    public func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        var made: [any TranscriberEngine] = []
        for locale in locales {
            guard let engine = try await ModernSpeechSupport.makeEngine(localeID: locale, options: options) else {
                throw EngineError.engineUnavailable("Conversation mode needs macOS 26 or later.")
            }
            made.append(engine)
        }
        lock.withLock { engines = made }

        let shared = SharedAudioCapture(source: capture, branchCount: locales.count)
        let branches = shared.branches
        let streams: [AsyncThrowingStream<TranscriptionEvent, Error>]
        do {
            streams = try await withThrowingTaskGroup(of: (Int, AsyncThrowingStream<TranscriptionEvent, Error>).self) { group in
                for (index, engine) in made.enumerated() {
                    group.addTask { (index, try await engine.events(from: branches[index])) }
                }
                var ordered = [AsyncThrowingStream<TranscriptionEvent, Error>?](repeating: nil, count: made.count)
                do {
                    for try await (index, stream) in group { ordered[index] = stream }
                } catch {
                    // A consumer that failed to start would leave the others waiting for audio forever.
                    shared.abort(error)
                    throw error
                }
                return ordered.compactMap { $0 }
            }
        } catch {
            for engine in made { await engine.stop() }
            throw error
        }

        let merger = Merger(locales: locales)
        return AsyncThrowingStream { continuation in
            let driver = Task {
                await merger.run(streams: streams, into: continuation)
            }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }

    public func stop() async {
        let current = lock.withLock { engines }
        for engine in current { await engine.stop() }
    }

    /// Serializes the recognizers' events through the arbiter.
    private actor Merger {
        private var arbiter: LanguageArbiter
        private let locales: [String]
        private let clock = ContinuousClock()
        private let start: ContinuousClock.Instant
        private var firstError: Error?
        private var emittedAnything = false
        private var remaining = 0
        private var continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?

        init(locales: [String]) {
            self.locales = locales
            arbiter = LanguageArbiter(locales: locales)
            start = clock.now
        }

        private var now: Double {
            let parts = (clock.now - start).components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }

        func run(streams: [AsyncThrowingStream<TranscriptionEvent, Error>], into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async {
            self.continuation = continuation
            remaining = streams.count
            await withTaskGroup(of: Void.self) { group in
                for (index, stream) in streams.enumerated() {
                    let locale = locales[index]
                    group.addTask { [self] in
                        do {
                            for try await event in stream { await ingest(event, from: locale) }
                        } catch {
                            await failed(error)
                        }
                        await streamEnded()
                    }
                }
                group.addTask { [self] in
                    // Finals wait a short while for the other recognizer; this clock releases them.
                    while !Task.isCancelled, await !isFinished {
                        try? await Task.sleep(for: .milliseconds(100))
                        await tick()
                    }
                }
            }
        }

        private var isFinished = false

        private func emit(_ events: [TranscriptionEvent]) {
            for event in events {
                emittedAnything = true
                continuation?.yield(event)
            }
        }

        private func ingest(_ event: TranscriptionEvent, from locale: String) {
            emit(arbiter.ingest(event, from: locale, now: now))
        }

        private func tick() { emit(arbiter.flush(now: now)) }

        private func failed(_ error: Error) { if firstError == nil { firstError = error } }

        private func streamEnded() {
            remaining -= 1
            guard remaining == 0 else { return }
            emit(arbiter.finish())
            isFinished = true
            // One recognizer failing is harmless when the other one carried the conversation.
            if let firstError, !emittedAnything {
                continuation?.finish(throwing: firstError)
            } else {
                continuation?.finish()
            }
        }
    }
}
