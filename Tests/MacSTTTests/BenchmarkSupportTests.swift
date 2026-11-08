import AVFoundation
import Foundation
import Testing

@testable import MacSTTCore

@Suite("Text metrics")
struct TextMetricsTests {
    @Test func identicalTextHasNoErrors() {
        #expect(TextMetrics.wordErrorRate(reference: "Open the shared spreadsheet.", hypothesis: "open the SHARED spreadsheet") == 0)
    }

    @Test func oneSubstitutionInFourWords() {
        #expect(TextMetrics.wordErrorRate(reference: "open the shared spreadsheet", hypothesis: "open the shared spread sheet") == 0.5)
        #expect(TextMetrics.wordErrorRate(reference: "open the shared spreadsheet", hypothesis: "open the shared worksheet") == 0.25)
    }

    @Test func deletionsAndInsertionsCount() {
        #expect(TextMetrics.wordErrorRate(reference: "a b c d", hypothesis: "a c d") == 0.25)
        #expect(TextMetrics.wordErrorRate(reference: "a b", hypothesis: "a b c d") == 1)
    }

    @Test func emptyReferenceIsHandled() {
        #expect(TextMetrics.wordErrorRate(reference: "", hypothesis: "") == 0)
        #expect(TextMetrics.wordErrorRate(reference: "", hypothesis: "x") == 1)
    }

    @Test func koreanCharacterErrorRateIgnoresSpacingAndPunctuation() {
        #expect(TextMetrics.characterErrorRate(reference: "공유된 스프레드시트를 열어 주세요.", hypothesis: "공유된스프레드시트를 열어주세요") == 0)
        #expect(TextMetrics.characterErrorRate(reference: "열어 주세요", hypothesis: "열어 주세오") == 0.2)
    }
}

@Suite("File audio capture")
struct FileAudioCaptureTests {
    /// 0.3 s silence, 0.4 s tone, 0.3 s silence at 16 kHz.
    private func makeTestFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(16_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let time = Double(i) / 16_000
            buffer.floatChannelData![0][i] = (0.3..<0.7).contains(time) ? Float(0.5 * sin(2 * .pi * 440 * time)) : 0
        }
        try file.write(from: buffer)
        return url
    }

    @Test func profileFindsTheSpeechWindow() throws {
        let url = try makeTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = try #require(FileAudioCapture.profile(of: url))
        #expect(abs(profile.duration - 1.0) < 0.001)
        #expect(abs(profile.speechStart - 0.3) < 0.04)
        #expect(abs(profile.speechEnd - 0.7) < 0.04)
    }

    @Test func profileOfMissingFileIsNil() {
        #expect(FileAudioCapture.profile(of: URL(fileURLWithPath: "/nonexistent/file.wav")) == nil)
    }

    @Test func streamsInRealTimeWithTrailingSilence() async throws {
        let url = try makeTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let capture = FileAudioCapture(url: url, tailSilence: 0.5)
        let clock = ContinuousClock()
        let begin = clock.now
        let stream = try await capture.start()
        var seconds = 0.0
        var silentTail = 0.0
        for await chunk in stream {
            seconds += chunk.duration
            if seconds > 1.0 { silentTail += chunk.duration }
        }
        let elapsed = begin.duration(to: clock.now)
        #expect(abs(seconds - 1.5) < 0.02)
        #expect(abs(silentTail - 0.5) < 0.02)
        // Real time: it must have taken about as long as the audio, not finished instantly.
        #expect(elapsed >= .milliseconds(1400))
        #expect(capture.startedAt != nil)
    }

    @Test func stopEndsTheStreamEarly() async throws {
        let url = try makeTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let capture = FileAudioCapture(url: url, tailSilence: 5)
        let stream = try await capture.start()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await capture.stop()
        }
        var seconds = 0.0
        for await chunk in stream { seconds += chunk.duration }
        #expect(seconds < 1.0)
    }

    @Test func unreadableFileFailsWithAClearError() async {
        let capture = FileAudioCapture(url: URL(fileURLWithPath: "/nonexistent/file.wav"))
        do {
            _ = try await capture.start()
            Issue.record("expected an error")
        } catch let error as EngineError {
            #expect(error.errorDescription?.contains("file.wav") == true)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
