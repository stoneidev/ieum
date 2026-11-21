import AVFoundation
import Foundation

/// The pause switch, shared between the interface and the audio thread.
public final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    public init() {}

    public var isPaused: Bool { lock.withLock { paused } }
    public func pause() { lock.withLock { paused = true } }
    public func resume() { lock.withLock { paused = false } }
}

/// While paused, the recognizer is handed silence instead of what the microphone hears, so what is said meanwhile is neither
/// recognized nor written down. Silence (not a gap) keeps the timeline whole and lets the recognizer finish the sentence it
/// was in the middle of; resuming simply carries on in the same transcript.
public struct PausableCapture: AudioCapture {
    private let inner: any AudioCapture
    private let gate: PauseGate

    public init(_ inner: any AudioCapture, gate: PauseGate) {
        self.inner = inner
        self.gate = gate
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let source = try await inner.start()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let gate = self.gate
        let task = Task {
            for await chunk in source {
                continuation.yield(gate.isPaused ? chunk.silenced() : chunk)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async { await inner.stop() }
}

extension AudioChunk {
    /// The same length and format, with nothing in it.
    func silenced() -> AudioChunk {
        let source = buffer
        guard let quiet = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameCapacity) else { return self }
        quiet.frameLength = source.frameLength
        let frames = Int(source.frameLength)
        let channels = Int(source.format.channelCount)
        if let data = quiet.floatChannelData {
            for channel in 0..<channels { data[channel].update(repeating: 0, count: frames) }
        } else if let data = quiet.int16ChannelData {
            for channel in 0..<channels { data[channel].update(repeating: 0, count: frames) }
        } else if let data = quiet.int32ChannelData {
            for channel in 0..<channels { data[channel].update(repeating: 0, count: frames) }
        }
        return AudioChunk(buffer: quiet, levelDB: AudioLevel.floorDB, duration: duration)
    }
}
