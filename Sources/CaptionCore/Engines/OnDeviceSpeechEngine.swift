import AVFoundation
import Foundation
import Speech

/// Decides when the legacy recognition task must be rolled over.
/// SFSpeechRecognizer sessions die after ~1 minute, so we restart on silence or after `maxSessionDuration`.
struct RolloverPolicy {
    let maxSessionDuration: TimeInterval
    let silenceDuration: TimeInterval
    private var detector: SilenceDetector
    private(set) var elapsed: TimeInterval = 0

    init(maxSessionDuration: TimeInterval = 50, silenceDuration: TimeInterval = 1.0, silenceThresholdDB: Float = SilenceDetector.defaultThresholdDB) {
        self.maxSessionDuration = maxSessionDuration
        self.silenceDuration = silenceDuration
        self.detector = SilenceDetector(thresholdDB: silenceThresholdDB)
    }

    /// Returns true when the current session should be ended before the next buffer.
    mutating func ingest(duration: TimeInterval, levelDB: Float) -> Bool {
        elapsed += duration
        detector.ingest(levelDB: levelDB, duration: duration)
        if elapsed >= maxSessionDuration { return true }
        return detector.hasHeardSpeech && detector.silentDuration >= silenceDuration
    }

    mutating func reset() {
        elapsed = 0
        detector.reset()
    }
}

/// Compatibility engine: on-device `SFSpeechRecognizer` with a rolling session manager.
actor OnDeviceSpeechEngine: TranscriberEngine {
    nonisolated var name: String { "SFSpeechRecognizer (on-device, rolling sessions)" }

    private struct Session {
        let id: Int
        let request: SFSpeechAudioBufferRecognitionRequest
        let task: SFSpeechRecognitionTask
    }

    /// Per-session bookkeeping shared with the recognizer's callback queue.
    private final class SessionState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var lastPartial = ""

        func notePartial(_ text: String) { lock.withLock { lastPartial = text } }
        func markFinished() { lock.withLock { finished = true } }
        /// Text that was shown as partial but never finalized (task ended with an error).
        func takeUnfinishedPartial() -> String? {
            lock.withLock {
                defer { finished = true }
                guard !finished else { return nil }
                return lastPartial.isEmpty ? nil : lastPartial
            }
        }
    }

    private let localeID: String
    private let recognizer: SFSpeechRecognizer
    private let callbackQueue: OperationQueue
    private let vocabulary: [String]
    private var capture: (any AudioCapture)?
    private var current: Session?
    private var live = Set<Int>()
    private var nextID = 0
    private var policy = RolloverPolicy()

    init(localeID: String, options: EngineOptions = EngineOptions()) throws {
        // Check first: constructing a recognizer for an unknown locale makes the system dump a log to stderr.
        let requested = Locale(identifier: localeID).identifier(.bcp47)
        guard SFSpeechRecognizer.supportedLocales().contains(where: { $0.identifier(.bcp47) == requested }),
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        else {
            throw EngineError.unsupportedLocale("Locale '\(localeID)' is not supported by SFSpeechRecognizer.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw EngineError.unsupportedLocale(
                "Locale '\(localeID)' has no on-device speech model. Enable it under System Settings > Keyboard > Dictation."
            )
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "caption.speech-callbacks"
        recognizer.queue = queue
        self.recognizer = recognizer
        self.callbackQueue = queue
        self.localeID = localeID
        self.vocabulary = options.vocabulary
    }

    /// On-device locales, as BCP-47 identifiers.
    nonisolated static func supportedLocaleIdentifiers() -> [String] {
        SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .map { $0.identifier(.bcp47) }
    }

    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        let status = await Self.requestAuthorization()
        guard status == .authorized else {
            throw EngineError.permissionDenied(
                "Speech recognition is not allowed (\(status)). Allow this app under "
                    + "System Settings > Privacy & Security > Speech Recognition, then start again."
            )
        }
        guard recognizer.isAvailable else {
            throw EngineError.engineUnavailable("The speech recognizer for '\(localeID)' is currently unavailable.")
        }
        let audio = try await capture.start()
        self.capture = capture

        return AsyncThrowingStream { continuation in
            let pump = Task { [self] in
                await self.pump(audio, into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                pump.cancel()
                Task { await capture.stop() }
            }
        }
    }

    func stop() async {
        await capture?.stop()
    }

    // MARK: Pump & rolling sessions

    private func pump(_ audio: AsyncStream<AudioChunk>, into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async {
        for await chunk in audio {
            if Task.isCancelled { break }
            if current == nil { startSession(continuation) }
            current?.request.append(chunk.buffer)
            if policy.ingest(duration: chunk.duration, levelDB: chunk.levelDB) {
                endCurrentSession()
            }
        }
        endCurrentSession()
        // A cancelled task cannot sleep (it would spin), and nobody is listening anymore anyway.
        if !Task.isCancelled { await drain() }
    }

    private func startSession(_ continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary

        let id = nextID
        nextID += 1
        live.insert(id)
        policy.reset()

        let state = SessionState()
        let localeID = self.localeID
        let finish: @Sendable () -> Void = { [weak self] in
            Task { await self?.sessionEnded(id) }
        }
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    state.markFinished()
                    continuation.yield(TranscriptionEvent(text: text, isFinal: true, locale: localeID))
                    finish()
                } else {
                    state.notePartial(text)
                    continuation.yield(TranscriptionEvent(text: text, isFinal: false, locale: localeID))
                }
            } else if error != nil {
                // Includes "no speech detected"; never lose text that was only shown as a partial.
                if let leftover = state.takeUnfinishedPartial() {
                    continuation.yield(TranscriptionEvent(text: leftover, isFinal: true, locale: localeID))
                }
                finish()
            }
        }
        current = Session(id: id, request: request, task: task)
    }

    private func endCurrentSession() {
        guard let session = current else { return }
        session.request.endAudio()
        current = nil
        policy.reset()
    }

    private func sessionEnded(_ id: Int) {
        live.remove(id)
    }

    /// Waits (bounded) for ended sessions to deliver their final results.
    private func drain() async {
        let deadline = ContinuousClock.now + .seconds(4)
        while !live.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
