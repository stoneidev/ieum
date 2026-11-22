import AVFoundation
import Testing

@testable import CaptionCore

@Suite("Pausing the captions")
struct PausableCaptureTests {
    private func loudChunk() -> AudioChunk {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buffer.frameLength = 1600
        for i in 0..<1600 { buffer.floatChannelData![0][i] = 0.5 }
        return AudioChunk(buffer: buffer)
    }

    private struct Scripted: AudioCapture {
        let chunks: [AudioChunk]
        func start() async throws -> AsyncStream<AudioChunk> {
            AsyncStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
        func stop() async {}
    }

    @Test func aSilencedChunkKeepsItsLengthAndHasNothingInIt() {
        let loud = loudChunk()
        let quiet = loud.silenced()
        #expect(quiet.buffer.frameLength == loud.buffer.frameLength)
        #expect(quiet.duration == loud.duration)
        #expect(quiet.levelDB < -100)
        #expect(quiet.buffer.floatChannelData![0][100] == 0)
    }

    @Test func soundPassesUntilPausedAndSilenceFollows() async throws {
        let gate = PauseGate()
        let capture = PausableCapture(Scripted(chunks: [loudChunk(), loudChunk()]), gate: gate)
        var levels: [Float] = []
        for await chunk in try await capture.start() { levels.append(chunk.levelDB) }
        #expect(levels.count == 2 && levels.allSatisfy { $0 > -20 })

        gate.pause()
        var paused: [Float] = []
        for await chunk in try await capture.start() { paused.append(chunk.levelDB) }
        #expect(paused.count == 2 && paused.allSatisfy { $0 < -100 })

        gate.resume()
        var again: [Float] = []
        for await chunk in try await capture.start() { again.append(chunk.levelDB) }
        #expect(again.allSatisfy { $0 > -20 })
    }
}
