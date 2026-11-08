import AVFoundation
import Foundation
import Testing

@testable import CaptionCore

private final class FakeSource: AudioCapture, @unchecked Sendable {
    let chunks: Int
    private let lock = NSLock()
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var failOnStart = false
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    init(chunks: Int) { self.chunks = chunks }

    func start() async throws -> AsyncStream<AudioChunk> {
        lock.withLock { startCount += 1 }
        if failOnStart { throw EngineError.captureFailed("no device") }
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        lock.withLock { self.continuation = continuation }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        for index in 0..<chunks {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 400)!
            buffer.frameLength = 160 + AVAudioFrameCount(index) // distinct lengths identify each chunk
            continuation.yield(AudioChunk(buffer: buffer))
        }
        return stream
    }

    func stop() async {
        lock.withLock { stopCount += 1 }
        continuation?.finish()
    }
}

@Suite("Shared audio capture")
struct SharedAudioCaptureTests {
    private func lengths(_ stream: AsyncStream<AudioChunk>, upTo count: Int) async -> [Int] {
        var result: [Int] = []
        for await chunk in stream {
            result.append(Int(chunk.buffer.frameLength))
            if result.count == count { break }
        }
        return result
    }

    @Test func everyBranchGetsTheSameChunksFromTheFirstOne() async throws {
        let source = FakeSource(chunks: 5)
        let shared = SharedAudioCapture(source: source, branchCount: 2)
        async let first = shared.branches[0].start()
        async let second = shared.branches[1].start()
        let (a, b) = try await (first, second)
        let seenA = await lengths(a, upTo: 5)
        let seenB = await lengths(b, upTo: 5)
        #expect(seenA == [160, 161, 162, 163, 164])
        #expect(seenB == seenA)
        #expect(source.startCount == 1)
    }

    @Test func sourceStartsOnlyWhenEveryBranchHasAskedForAudio() async throws {
        let source = FakeSource(chunks: 1)
        let shared = SharedAudioCapture(source: source, branchCount: 2)
        let early = Task { try await shared.branches[0].start() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(source.startCount == 0)
        _ = try await shared.branches[1].start()
        _ = try await early.value
        #expect(source.startCount == 1)
    }

    @Test func sourceStopsOnlyAfterEveryBranchStopped() async throws {
        let source = FakeSource(chunks: 1)
        let shared = SharedAudioCapture(source: source, branchCount: 2)
        async let first = shared.branches[0].start()
        async let second = shared.branches[1].start()
        _ = try await (first, second)
        await shared.branches[0].stop()
        #expect(source.stopCount == 0)
        await shared.branches[1].stop()
        #expect(source.stopCount == 1)
    }

    @Test func aFailingSourceFailsEveryBranch() async throws {
        let source = FakeSource(chunks: 1)
        source.failOnStart = true
        let shared = SharedAudioCapture(source: source, branchCount: 2)
        async let first: Result<AsyncStream<AudioChunk>, Error> = {
            do { return .success(try await shared.branches[0].start()) } catch { return .failure(error) }
        }()
        async let second: Result<AsyncStream<AudioChunk>, Error> = {
            do { return .success(try await shared.branches[1].start()) } catch { return .failure(error) }
        }()
        let results = await [first, second]
        for result in results {
            if case .success = result { Issue.record("expected a failure") }
        }
    }
}
