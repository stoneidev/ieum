import Foundation

/// A call: the other side comes through system audio and the person at this Mac through the microphone. Each is
/// recognized on its own in the language that side speaks, so the transcript knows who said what without guessing
/// the language or telling voices apart. The microphone side passes through `EchoGuard`, because with speakers
/// the microphone also hears the other side.
public final class CallEngine: TranscriberEngine, @unchecked Sendable {
    public typealias Started = (engine: any TranscriberEngine, events: AsyncThrowingStream<TranscriptionEvent, Error>)
    public typealias Starter = @Sendable (_ locale: String, _ options: EngineOptions, _ capture: any AudioCapture) async throws -> Started

    public var name: String { "Call (them \(theirLocale), me \(myLocale))" }

    private let theirLocale: String
    private let myLocale: String
    private let options: EngineOptions
    private let microphone: any AudioCapture
    private let starter: Starter
    private let lock = NSLock()
    private var engines: [any TranscriberEngine] = []

    /// - Parameters:
    ///   - theirLocale: the language the other side speaks (system audio).
    ///   - myLocale: the language the person at this Mac speaks (microphone).
    public init(
        theirLocale: String, myLocale: String, options: EngineOptions, microphone: any AudioCapture,
        starter: @escaping Starter = { locale, options, capture in
            try await EngineFactory.start(choice: .auto, localeID: locale, options: options, capture: capture)
        }
    ) {
        self.theirLocale = theirLocale
        self.myLocale = myLocale
        self.options = options
        self.microphone = microphone
        self.starter = starter
    }

    /// `capture` is the system audio, the other side.
    public func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        // English sentences close well on their own; closing them at a pause damages the next sentence's first words.
        let theirOptions = Self.options(options, for: theirLocale)
        let myOptions = Self.options(options, for: myLocale)
        let starter = self.starter
        let (theirLocale, myLocale, microphone) = (self.theirLocale, self.myLocale, self.microphone)
        let results = await withTaskGroup(of: (Speaker, Result<Started, Error>).self) { group -> [(Speaker, Result<Started, Error>)] in
            group.addTask {
                do { return (.them, .success(try await starter(theirLocale, theirOptions, capture))) } catch { return (.them, .failure(error)) }
            }
            group.addTask {
                do { return (.me, .success(try await starter(myLocale, myOptions, microphone))) } catch { return (.me, .failure(error)) }
            }
            var collected: [(Speaker, Result<Started, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var started: [Speaker: Started] = [:]
        var failure: Error?
        for (speaker, result) in results {
            switch result {
            case .success(let value): started[speaker] = value
            case .failure(let error): if failure == nil || speaker == .me { failure = error }
            }
        }
        if let failure {
            for value in started.values { await value.engine.stop() }
            await capture.stop()
            await microphone.stop()
            throw failure
        }
        guard let them = started[.them], let me = started[.me] else { throw EngineError.engineUnavailable("The call could not be started.") }
        lock.withLock { engines = [them.engine, me.engine] }

        let merger = Merger()
        return AsyncThrowingStream { continuation in
            let driver = Task { [weak self] in
                await merger.run(them: them.events, me: me.events, into: continuation)
                // However it ended, both sides stop together: a call with one dead side would look healthy.
                await self?.stop()
            }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }

    private static func options(_ base: EngineOptions, for locale: String) -> EngineOptions {
        var result = base
        if locale.hasPrefix("en") { result.pauseFinalization = nil }
        return result
    }

    public func stop() async {
        let current = lock.withLock { engines }
        for engine in current { await engine.stop() }
        // An engine that failed to start left its capture running; stopping again is harmless.
        await microphone.stop()
    }

    private actor Merger {
        private var guardrail = EchoGuard()

        func run(
            them: AsyncThrowingStream<TranscriptionEvent, Error>,
            me: AsyncThrowingStream<TranscriptionEvent, Error>,
            into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
        ) async {
            await withTaskGroup(of: Error?.self) { group in
                group.addTask { await self.pump(them, as: .them, into: continuation) }
                group.addTask { await self.pump(me, as: .me, into: continuation) }
                var firstError: Error?
                // The first side to end (cleanly or not) ends the call. When the system audio dies (display asleep,
                // output changed) the microphone alone must not carry on as if all were well.
                for await error in group {
                    // Cancelling the other side ends its stream too; that is not a failure.
                    if let error, firstError == nil, !(error is CancellationError) { firstError = error }
                    group.cancelAll()
                }
                if let firstError { continuation.finish(throwing: firstError) } else { continuation.finish() }
            }
        }

        private func pump(
            _ stream: AsyncThrowingStream<TranscriptionEvent, Error>, as speaker: Speaker,
            into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
        ) async -> Error? {
            do {
                for try await event in stream {
                    if let tagged = filter(event, as: speaker) { continuation.yield(tagged) }
                }
                return nil
            } catch {
                return error
            }
        }

        private func filter(_ event: TranscriptionEvent, as speaker: Speaker) -> TranscriptionEvent? {
            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var tagged = event
            tagged.speaker = speaker
            switch speaker {
            case .them:
                guardrail.noteTheirs(text, at: event.timestamp)
                return tagged
            case .me:
                guard guardrail.isEcho(text, at: event.timestamp) else { return tagged }
                // A dropped sentence still ends the line being shown, so no half-heard "Me" line is left behind.
                if event.isFinal {
                    let empty = TranscriptionEvent(text: "", isFinal: true, locale: event.locale, timestamp: event.timestamp,
                                                   audioStart: event.audioStart, audioEnd: event.audioEnd, speaker: .me)
                    return empty
                }
                return nil
            }
        }
    }
}
