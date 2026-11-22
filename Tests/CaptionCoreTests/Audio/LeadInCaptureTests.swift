import AVFoundation
import Testing

@testable import CaptionCore

@Suite("Session lead-in silence")
struct LeadInCaptureTests {
    private func loudChunk(frames: AVAudioFrameCount = 1600, sampleRate: Double = 16_000) -> AudioChunk {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0.5 }
        return AudioChunk(buffer: buffer)
    }

    private struct Scripted: AudioCapture {
        let chunks: [AudioChunk]
        func start() async throws -> AsyncStream<AudioChunk> {
            let chunks = self.chunks
            return AsyncStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
        func stop() async {}
    }

    private final class StopTracking: AudioCapture, @unchecked Sendable {
        let chunks: [AudioChunk]
        private let lock = NSLock()
        private(set) var stopCount = 0
        init(chunks: [AudioChunk]) { self.chunks = chunks }
        func start() async throws -> AsyncStream<AudioChunk> {
            let chunks = self.chunks
            return AsyncStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
        func stop() async { lock.withLock { stopCount += 1 } }
    }

    @Test func silenceChunksSumToTheRequestedDuration() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let chunks = LeadInCapture.silenceChunks(format: format, totalDuration: 0.5, chunkDuration: 0.1)
        let total = chunks.reduce(0.0) { $0 + $1.duration }
        #expect(abs(total - 0.5) < 0.001)
        #expect(chunks.count == 5)
        #expect(chunks.allSatisfy { $0.levelDB < -100 })
        #expect(chunks.allSatisfy { $0.buffer.floatChannelData![0][0] == 0 })
    }

    @Test func zeroDurationProducesNoSilence() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        #expect(LeadInCapture.silenceChunks(format: format, totalDuration: 0, chunkDuration: 0.1).isEmpty)
    }

    @Test func liveChunksFollowLeadInSilenceInOrder() async throws {
        let first = loudChunk()
        let second = loudChunk(frames: 800)
        let capture = LeadInCapture(Scripted(chunks: [first, second]), duration: 0.5)
        var received: [AudioChunk] = []
        for await chunk in try await capture.start() { received.append(chunk) }

        let leadIn = received.filter { $0.levelDB < -100 }
        let live = received.filter { $0.levelDB > -20 }
        #expect(abs(leadIn.reduce(0.0) { $0 + $1.duration } - 0.5) < 0.001)
        #expect(live.count == 2)
        #expect(live[0].buffer.frameLength == first.buffer.frameLength)
        #expect(live[1].buffer.frameLength == second.buffer.frameLength)
        // Every silence chunk comes before any live audio.
        let firstLive = received.firstIndex { $0.levelDB > -20 }!
        #expect(received[..<firstLive].allSatisfy { $0.levelDB < -100 })
    }

    @Test func emptySourceEmitsNothing() async throws {
        let capture = LeadInCapture(Scripted(chunks: []), duration: 0.5)
        var count = 0
        for await _ in try await capture.start() { count += 1 }
        #expect(count == 0)
    }

    @Test func stopForwardsToTheInnerCapture() async {
        let inner = StopTracking(chunks: [loudChunk()])
        let capture = LeadInCapture(inner)
        await capture.stop()
        #expect(inner.stopCount == 1)
    }
}
