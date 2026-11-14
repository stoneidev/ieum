import Foundation

/// What the sound reaching the recognizer says about the setup, in terms a person can act on.
public enum InputAdvice: Equatable, Sendable {
    case good
    /// Nothing but silence: muted, the wrong microphone, or nothing playing.
    case silent
    /// Sound arrives but never reaches the level of speech: too far from the microphone.
    case tooQuiet
    /// The sound is so loud it distorts.
    case tooLoud
}

/// Watches the level of the incoming sound and says when the setup, not the speaker, is the problem. Silence is only reported
/// after a few seconds, and quiet only after a long stretch, because speakers pause.
public struct InputLevelAdvisor: Sendable {
    /// Below this the input is silence, not a quiet room (a microphone's own noise sits well above it).
    static let silentBelowDB: Float = -62
    /// Ordinary speech at a normal distance is far above this; a stretch that never reaches it is out of range.
    static let speechAboveDB: Float = -42
    static let clippingAboveDB: Float = -6
    static let silentAfter: TimeInterval = 6
    static let quietAfter: TimeInterval = 25
    static let loudWindow: TimeInterval = 2

    private var samples: [(level: Float, duration: TimeInterval)] = []
    private var heard: TimeInterval = 0
    /// 0...1 for a meter: fast to rise, slow to fall.
    public private(set) var meter: Float = 0

    public init() {}

    public mutating func ingest(levelDB: Float, duration: TimeInterval) {
        guard duration > 0 else { return }
        samples.append((levelDB, duration))
        heard += duration
        // Keep only what the longest rule looks at.
        var kept: TimeInterval = 0
        var keep = 0
        for sample in samples.reversed() {
            keep += 1
            kept += sample.duration
            if kept >= Self.quietAfter { break }
        }
        if samples.count > keep { samples.removeFirst(samples.count - keep) }

        let target = min(1, max(0, (levelDB + 60) / 50))
        meter = target > meter ? target : max(target, meter - Float(duration) * 1.5)
    }

    public var advice: InputAdvice {
        if share(above: Self.clippingAboveDB, in: Self.loudWindow) >= 0.3, heard >= Self.loudWindow { return .tooLoud }
        if heard >= Self.silentAfter, peak(in: Self.silentAfter) < Self.silentBelowDB { return .silent }
        if heard >= Self.quietAfter, peak(in: Self.quietAfter) < Self.speechAboveDB { return .tooQuiet }
        return .good
    }

    private func peak(in seconds: TimeInterval) -> Float {
        var covered: TimeInterval = 0
        var best = -Float.infinity
        for sample in samples.reversed() {
            best = max(best, sample.level)
            covered += sample.duration
            if covered >= seconds { break }
        }
        return best
    }

    private func share(above level: Float, in seconds: TimeInterval) -> Double {
        var covered: TimeInterval = 0, loud: TimeInterval = 0
        for sample in samples.reversed() {
            covered += sample.duration
            if sample.level > level { loud += sample.duration }
            if covered >= seconds { break }
        }
        return covered > 0 ? loud / covered : 0
    }
}

/// Feeds an advisor from the audio thread and hands the result to the interface a few times a second, and at once when the advice changes.
public final class InputLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var advisor = InputLevelAdvisor()
    private var lastAdvice = InputAdvice.good
    private var lastPublished = Date.distantPast
    private let onUpdate: @Sendable (InputAdvice, Float) -> Void

    public init(onUpdate: @escaping @Sendable (InputAdvice, Float) -> Void) {
        self.onUpdate = onUpdate
    }

    public func ingest(levelDB: Float, duration: TimeInterval) {
        let update: (InputAdvice, Float)? = lock.withLock {
            advisor.ingest(levelDB: levelDB, duration: duration)
            let advice = advisor.advice
            let now = Date()
            guard advice != lastAdvice || now.timeIntervalSince(lastPublished) >= 0.1 else { return nil }
            lastAdvice = advice
            lastPublished = now
            return (advice, advisor.meter)
        }
        if let update { onUpdate(update.0, update.1) }
    }
}

/// Passes the sound on unchanged and lets a monitor look at its level on the way.
public struct MeteredCapture: AudioCapture {
    private let inner: any AudioCapture
    private let monitor: InputLevelMonitor

    public init(_ inner: any AudioCapture, monitor: InputLevelMonitor) {
        self.inner = inner
        self.monitor = monitor
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let source = try await inner.start()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let monitor = self.monitor
        let task = Task {
            for await chunk in source {
                monitor.ingest(levelDB: chunk.levelDB, duration: chunk.duration)
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async { await inner.stop() }
}
