import AVFoundation
import Foundation

/// Pads the start of a live session with silence so the first spoken words are not lost.
///
/// SpeechAnalyzer reports in roughly one-second bursts. When speech begins at sample 0 of a new session
/// (common after a settings restart while someone is already talking), the first words are often missing
/// (`docs/TRANSCRIPTION-RESEARCH.md`: English numbers passage WER 13.3 % → 6.7 % with 0.5 s of lead-in).
///
/// Silence is queued as a burst matching the first live chunk's format, not wall-clock paced, so live audio
/// is not delayed — only the recognizer's audio timeline is padded. File benches keep their own lead-in in
/// the audio file and should not wrap with this type.
public struct LeadInCapture: AudioCapture {
    /// Duration that recovered the first words in the transcription research (0.5 s of silence before speech).
    public static let defaultDuration: TimeInterval = 0.5

    private let inner: any AudioCapture
    private let duration: TimeInterval

    public init(_ inner: any AudioCapture, duration: TimeInterval = Self.defaultDuration) {
        self.inner = inner
        self.duration = max(0, duration)
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let source = try await inner.start()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let duration = self.duration
        let task = Task {
            var primed = false
            for await chunk in source {
                if Task.isCancelled { break }
                if !primed {
                    for silence in Self.silenceChunks(format: chunk.buffer.format, totalDuration: duration, chunkDuration: chunk.duration) {
                        continuation.yield(silence)
                    }
                    primed = true
                }
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async { await inner.stop() }

    /// Zeroed PCM chunks that sum to about `totalDuration`, using `format` and roughly `chunkDuration` each.
    /// Exposed for tests: the wrapper only needs the first live chunk's format before it can pad.
    static func silenceChunks(
        format: AVAudioFormat,
        totalDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) -> [AudioChunk] {
        let sampleRate = format.sampleRate
        guard sampleRate > 0, totalDuration > 0 else { return [] }
        let preferred = chunkDuration > 0 ? chunkDuration : 0.1
        let framesPerChunk = max(1, AVAudioFrameCount(preferred * sampleRate))
        var remaining = totalDuration
        var chunks: [AudioChunk] = []
        while remaining > 0 {
            let frames = min(framesPerChunk, AVAudioFrameCount(remaining * sampleRate))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
            buffer.frameLength = frames
            let count = Int(frames)
            let channels = Int(format.channelCount)
            if let data = buffer.floatChannelData {
                for channel in 0..<channels { data[channel].update(repeating: 0, count: count) }
            } else if let data = buffer.int16ChannelData {
                for channel in 0..<channels { data[channel].update(repeating: 0, count: count) }
            } else if let data = buffer.int32ChannelData {
                for channel in 0..<channels { data[channel].update(repeating: 0, count: count) }
            }
            chunks.append(AudioChunk(buffer: buffer))
            remaining -= Double(frames) / sampleRate
        }
        return chunks
    }
}
