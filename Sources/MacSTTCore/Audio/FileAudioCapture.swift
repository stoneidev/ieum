import AVFoundation
import Foundation

/// Plays an audio file into the engines at real-time speed, followed by silence so the recognizer can finalize.
/// Used by the benchmark: it exercises the same code path as a live microphone, with repeatable input.
public final class FileAudioCapture: AudioCapture, @unchecked Sendable {
    public struct Profile: Sendable, Equatable {
        public let duration: TimeInterval
        /// Audio-relative time of the first and last 20 ms window above the silence threshold.
        public let speechStart: TimeInterval
        public let speechEnd: TimeInterval
    }

    public let url: URL
    private let tailSilence: TimeInterval
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var started: ContinuousClock.Instant?

    public init(url: URL, tailSilence: TimeInterval = 2.5) {
        self.url = url
        self.tailSilence = tailSilence
    }

    /// The moment `start()` began streaming, i.e. audio time zero.
    public var startedAt: ContinuousClock.Instant? { lock.withLock { started } }

    /// Finds where speech starts and ends in the file (nil when it cannot be read or holds no speech).
    public static func profile(of url: URL, thresholdDB: Float = -50) -> Profile? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let window = AVAudioFrameCount(format.sampleRate * 0.02)
        guard window > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else { return nil }
        var frame: AVAudioFramePosition = 0
        var first: TimeInterval?
        var last: TimeInterval?
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: window) } catch { return nil }
            if buffer.frameLength == 0 { break }
            let time = Double(frame) / format.sampleRate
            if AudioLevel.rmsDB(of: buffer) > thresholdDB {
                if first == nil { first = time }
                last = time + Double(buffer.frameLength) / format.sampleRate
            }
            frame += AVAudioFramePosition(buffer.frameLength)
        }
        guard let first, let last else { return nil }
        return Profile(duration: Double(file.length) / format.sampleRate, speechStart: first, speechEnd: last)
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw EngineError.captureFailed("Cannot read audio file \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let format = file.processingFormat
        let chunkFrames = AVAudioFrameCount(format.sampleRate * 0.02 * 5) // 100 ms
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let clock = ContinuousClock()
        let begin = clock.now
        let tail = tailSilence
        let producer = Task {
            var sent: TimeInterval = 0
            func emit(_ buffer: AVAudioPCMBuffer) async {
                continuation.yield(AudioChunk(buffer: buffer))
                sent += Double(buffer.frameLength) / format.sampleRate
                // Absolute deadlines: no drift however long the file is.
                try? await clock.sleep(until: begin + .seconds(sent), tolerance: .milliseconds(2))
            }
            while !Task.isCancelled, file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
                      (try? file.read(into: buffer, frameCount: chunkFrames)) != nil, buffer.frameLength > 0 else { break }
                await emit(buffer)
            }
            var remaining = tail
            while !Task.isCancelled, remaining > 0 {
                let frames = min(chunkFrames, AVAudioFrameCount(remaining * format.sampleRate))
                guard frames > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
                silence.frameLength = frames
                if let data = silence.floatChannelData {
                    for channel in 0..<Int(format.channelCount) { data[channel].update(repeating: 0, count: Int(frames)) }
                }
                await emit(silence)
                remaining -= Double(frames) / format.sampleRate
            }
            continuation.finish()
        }
        lock.withLock {
            task = producer
            self.continuation = continuation
            started = begin
        }
        return stream
    }

    public func stop() async {
        let (task, continuation) = lock.withLock { (self.task, self.continuation) }
        task?.cancel()
        continuation?.finish()
    }
}
