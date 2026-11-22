import Foundation

/// Audio-relative clock of how far capture has advanced and when speech was last heard.
///
/// Used by `FastResultsSafetyNet` to tell a truncated fast final (speech still going past `audioEnd`) from a
/// normal one. Thresholds match `EndpointDetector`: clearly above the recent noise floor, and never quieter than
/// `absoluteFloorDB`.
public final class SpeechActivityClock: @unchecked Sendable {
    public let marginDB: Float
    public let absoluteFloorDB: Float

    private let lock = NSLock()
    private var fed = 0.0
    private var lastSpeech = 0.0
    private var recent: [(level: Float, duration: TimeInterval)] = []
    private var recentTotal: TimeInterval = 0
    private let windowSeconds: TimeInterval = 5
    private let maxFloorDB: Float = -40

    public init(marginDB: Float = 12, absoluteFloorDB: Float = -50) {
        self.marginDB = marginDB
        self.absoluteFloorDB = absoluteFloorDB
    }

    public var fedSeconds: Double { lock.withLock { fed } }
    public var lastSpeechAt: Double { lock.withLock { lastSpeech } }

    public func ingest(levelDB: Float, duration: TimeInterval) {
        guard duration > 0 else { return }
        lock.withLock {
            fed += duration
            remember(levelDB, duration: duration)
            if levelDB > max(noiseFloor + marginDB, absoluteFloorDB) {
                lastSpeech = fed
            }
        }
    }

    /// Test helper: set the watermark without audio.
    public func setForTesting(fedSeconds: Double, lastSpeechAt: Double) {
        lock.withLock {
            fed = fedSeconds
            lastSpeech = lastSpeechAt
        }
    }

    private var noiseFloor: Float {
        min(recent.map(\.level).min() ?? maxFloorDB, maxFloorDB)
    }

    private func remember(_ level: Float, duration: TimeInterval) {
        recent.append((max(level, -100), duration))
        recentTotal += duration
        while recentTotal > windowSeconds, recent.count > 1 {
            recentTotal -= recent.removeFirst().duration
        }
    }
}

/// Forwards audio unchanged while updating a `SpeechActivityClock`.
public struct TrackingCapture: AudioCapture {
    private let inner: any AudioCapture
    private let clock: SpeechActivityClock

    public init(_ inner: any AudioCapture, clock: SpeechActivityClock) {
        self.inner = inner
        self.clock = clock
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let source = try await inner.start()
        let clock = self.clock
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let task = Task {
            for await chunk in source {
                clock.ingest(levelDB: chunk.levelDB, duration: chunk.duration)
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async { await inner.stop() }
}
