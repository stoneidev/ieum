import AVFoundation
import CoreAudio
import Foundation
import Testing

@testable import IeumCore

private let utc = TimeZone(identifier: "UTC")!
// 2024-05-06T07:08:09.250Z
private let sampleDate = Date(timeIntervalSince1970: 1_714_979_289.25)

private func event(_ text: String, final: Bool, start: Double? = nil, end: Double? = nil) -> TranscriptionEvent {
    TranscriptionEvent(text: text, isFinal: final, locale: "ko-KR", timestamp: sampleDate, audioStart: start, audioEnd: end)
}


/// `#expect` cannot call mutating members, so tests drive the value types through reference wrappers.
private final class FormatterBox {
    private var formatter: OutputFormatter
    init(format: OutputFormat, interactive: Bool = true, columns: Int? = nil, timeZone: TimeZone = .current) {
        formatter = OutputFormatter(format: format, interactive: interactive, columns: columns, timeZone: timeZone)
    }
    @discardableResult func render(_ event: TranscriptionEvent) -> String { formatter.render(event) }
    func finish() -> String { formatter.finish() }
}

private final class PolicyBox {
    private var policy = RolloverPolicy()
    var elapsed: TimeInterval { policy.elapsed }
    @discardableResult func ingest(duration: TimeInterval, levelDB: Float) -> Bool { policy.ingest(duration: duration, levelDB: levelDB) }
    func reset() { policy.reset() }
}

private func parse(_ line: String) throws -> [String: Any] {
    let data = Data(line.trimmingCharacters(in: .newlines).utf8)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("JSONL output")
struct JSONLTests {
    @Test func finalLineHasSpecFieldsInOrder() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        let line = f.render(event("안녕하세요", final: true))
        #expect(line.hasSuffix("\n"))
        #expect(line == "{\"timestamp\":\"2024-05-06T07:08:09.250Z\",\"isFinal\":true,\"text\":\"안녕하세요\",\"locale\":\"ko-KR\"}\n")
        let object = try parse(line)
        #expect(object["isFinal"] as? Bool == true)
        #expect(object["text"] as? String == "안녕하세요")
        #expect(object["locale"] as? String == "ko-KR")
    }

    @Test func partialIsEmittedWithIsFinalFalse() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        let object = try parse(f.render(event("hel", final: false)))
        #expect(object["isFinal"] as? Bool == false)
    }

    @Test func escapesQuotesNewlinesAndSlashes() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        let line = f.render(event("say \"hi\"\nback\\slash a/b", final: true))
        #expect(line.filter { $0 == "\n" }.count == 1)
        #expect(try parse(line)["text"] as? String == "say \"hi\"\nback\\slash a/b".trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(line.contains("a/b"))
    }

    @Test func includesAudioRangeWhenPresent() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        let object = try parse(f.render(event("x", final: true, start: 1.5, end: 2.25)))
        #expect(object["audioStart"] as? Double == 1.5)
        #expect(object["audioEnd"] as? Double == 2.25)
    }

    @Test func emptyFinalProducesNothing() {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        #expect(f.render(event("  ", final: true)).isEmpty)
    }

    @Test func finishPromotesPendingPartialOnce() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        _ = f.render(event("unfinished", final: false))
        let flushed = f.finish()
        #expect(try parse(flushed)["isFinal"] as? Bool == true)
        #expect(f.finish().isEmpty)
    }
}

@Suite("Text output")
struct TextTests {
    @Test func partialRendersInPlace() {
        let f = FormatterBox(format: .text, timeZone: utc)
        #expect(f.render(event("hello wor", final: false)) == "\r\u{1B}[Khello wor")
        #expect(f.render(event("hello world", final: false)) == "\r\u{1B}[Khello world")
    }

    @Test func finalPrintsTimestampedLineAndClearsPartial() {
        let f = FormatterBox(format: .text, timeZone: utc)
        _ = f.render(event("hello", final: false))
        #expect(f.render(event("hello world", final: true)) == "\r\u{1B}[K[07:08:09] hello world\n")
    }

    @Test func nonInteractiveSuppressesPartialsAndEscapes() {
        let f = FormatterBox(format: .text, interactive: false, timeZone: utc)
        #expect(f.render(event("par", final: false)).isEmpty)
        #expect(f.render(event("done", final: true)) == "[07:08:09] done\n")
    }

    @Test func finishCommitsPendingPartial() {
        let f = FormatterBox(format: .text, timeZone: utc)
        _ = f.render(event("cut off", final: false))
        #expect(f.finish() == "\r\u{1B}[K[07:08:09] cut off\n")
        #expect(f.finish().isEmpty)
    }

    @Test func emptyFinalClearsLiveLine() {
        let f = FormatterBox(format: .text, timeZone: utc)
        _ = f.render(event("noise", final: false))
        #expect(f.render(event("", final: true)) == OutputFormatter.clearLine)
    }

    @Test func longPartialKeepsTailWithinColumns() {
        let tail = OutputFormatter.tail("0123456789012345678901234567890", columns: 20)
        #expect(tail.hasPrefix("…") && tail.hasSuffix("890"))
        #expect(OutputFormatter.displayWidth(tail) <= 16)
    }

    @Test func wideCharactersCountAsTwoColumns() {
        #expect(OutputFormatter.displayWidth("한글ab") == 6)
        let tail = OutputFormatter.tail("안녕하세요 반갑습니다 오늘도 좋은 하루 되세요", columns: 20)
        #expect(OutputFormatter.displayWidth(tail) <= 16)
        #expect(tail.hasPrefix("…") && tail.hasSuffix("되세요"))
        #expect(OutputFormatter.tail("short", columns: 80) == "short")
    }
}

@Suite("Repetition guard")
struct RepetitionTests {
    @Test func collapsesLoopedPhrase() {
        let phrase = "여러의 교회도 보존되었습니다. 심지어 교회가 어떤 소유를 통과한 것도 여러분 때문에"
        let looped = "앞 문장입니다. " + Array(repeating: phrase, count: 12).joined(separator: " ") + " 끝"
        #expect(RepetitionGuard.collapse(looped) == "앞 문장입니다. \(phrase) 끝")
    }

    @Test func collapsesRepeatedSingleWordOnlyWhenExcessive() {
        #expect(RepetitionGuard.collapse("a b c 네 네 네 네 네 d e") == "a b c 네 d e")
        #expect(RepetitionGuard.collapse("a b c 네 네 네 d e f") == "a b c 네 네 네 d e f")
    }

    @Test func leavesNormalTextAlone() {
        let text = "this is a perfectly normal sentence with no loops at all"
        #expect(RepetitionGuard.collapse(text) == text)
    }

    @Test func formatterAppliesGuard() throws {
        let f = FormatterBox(format: .jsonl, timeZone: utc)
        let looped = Array(repeating: "그런데도 교회가 전진하지 못한다면 성장도 없고", count: 6).joined(separator: " ")
        let object = try parse(f.render(event(looped, final: true)))
        #expect(object["text"] as? String == "그런데도 교회가 전진하지 못한다면 성장도 없고")
    }
}

@Suite("Polish guard")
struct PolishGuardTests {
    @Test func acceptsPunctuationAndSpacingFixes() {
        #expect(PolishGuard.accepts(original: "the quick brown fox jumps over the lazy dog", candidate: "The quick brown fox jumps over the lazy dog."))
        #expect(PolishGuard.accepts(original: "파드가 계속 재시작 됩니다", candidate: "파드가 계속 재시작됩니다."))
    }

    @Test func rejectsTranslationQuestionsAndDeletions() {
        let original = "여러의 교회도 보존 되었습니다 심지어 교회가 어떤 소유를 통과한 것도 여러분 때문에"
        #expect(!PolishGuard.accepts(original: original, candidate: "Your church has been preserved, and even the ownership has passed through you."))
        #expect(!PolishGuard.accepts(original: "오늘 쿠베르네티스 클러스터에 배포를 했는데 파드가 계속 재시작 됩니다", candidate: "파드가 계속 재시작되는 이유는 무엇인가요?"))
        #expect(!PolishGuard.accepts(original: "그런데도 교회가 전진하지 못한다면 성장도 없고", candidate: "성장이 없고 교회가 전진하지 못한다면"))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!PolishGuard.accepts(original: "hello", candidate: "  "))
    }

    @Test func nonFinalEventsAreNeverPolished() async {
        let polisher = FinalTextPolisher { _ in "CHANGED" }
        let partial = event("hello", final: false)
        #expect(await polisher.apply(to: partial) == partial)
    }

    @Test func appliesAcceptedAndKeepsRejected() async {
        let good = FinalTextPolisher { _ in "Hello world." }
        #expect(await good.apply(to: event("hello world", final: true)).text == "Hello world.")
        let bad = FinalTextPolisher { _ in "completely different sentence" }
        #expect(await bad.apply(to: event("hello world", final: true)).text == "hello world")
        let none = FinalTextPolisher { _ in nil }
        #expect(await none.apply(to: event("hello world", final: true)).text == "hello world")
    }
}

@Suite("Engine options")
struct EngineOptionsTests {
    @Test func parsesVocabularyFile() {
        let text = "# names\n  Kubernetes \n\n김철수\r\n#skip\nSwiftUI\n"
        #expect(EngineOptions.parseVocabulary(text) == ["Kubernetes", "김철수", "SwiftUI"])
    }

    @Test func defaultsFavorSpeed() {
        let options = EngineOptions()
        #expect(options.fast && options.useVAD && options.vocabulary.isEmpty)
    }
}

@Suite("Pipeline")
struct PipelineTests {
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [String] = []
        func add(_ s: String) { lock.withLock { chunks.append(s) } }
        var joined: String { lock.withLock { chunks.joined() } }
    }

    @Test func finishIsIdempotentAndBlocksLateEvents() {
        let sink = Sink()
        let pipeline = OutputPipeline(formatter: OutputFormatter(format: .text, timeZone: utc), write: sink.add)
        pipeline.handle(event("partial", final: false))
        pipeline.finish()
        pipeline.finish()
        pipeline.handle(event("late", final: true))
        #expect(sink.joined == "\r\u{1B}[Kpartial\r\u{1B}[K[07:08:09] partial\n")
    }
}

@Suite("Audio helpers")
struct AudioTests {
    private func buffer(frames: Int, sampleRate: Double = 16_000, _ sample: (Int) -> Float) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { buffer.floatChannelData![0][i] = sample(i) }
        return buffer
    }

    @Test func rmsOfSilenceIsFloor() throws {
        #expect(AudioLevel.rmsDB(of: try buffer(frames: 100) { _ in 0 }) == AudioLevel.floorDB)
    }

    @Test func rmsOfFullScaleSquareIsZeroDB() throws {
        let db = AudioLevel.rmsDB(of: try buffer(frames: 100) { _ in 1 })
        #expect(abs(db) < 0.001)
        let half = AudioLevel.rmsDB(of: try buffer(frames: 100) { _ in 0.5 })
        #expect(abs(half - (-6.0206)) < 0.01)
    }

    @Test func chunkDurationFromSampleRate() throws {
        let chunk = AudioChunk(buffer: try buffer(frames: 8000) { _ in 0.1 })
        #expect(abs(chunk.duration - 0.5) < 1e-9)
    }

    @Test func copyIsIndependent() throws {
        let original = try buffer(frames: 4) { Float($0) }
        let copy = try #require(original.copied())
        original.floatChannelData![0][0] = 99
        #expect(copy.floatChannelData![0][0] == 0)
        #expect(copy.floatChannelData![0][3] == 3)
    }

    @Test func loudestChannelMonoPicksTheVoiceChannel() throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, interleaved: false, channelLayout: layout)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        for c in 0..<4 { for i in 0..<64 { buffer.floatChannelData![c][i] = 0 } }
        for i in 0..<64 { buffer.floatChannelData![3][i] = 0.5 }
        let mono = try #require(buffer.loudestChannelMono())
        #expect(mono.format.channelCount == 1 && mono.frameLength == 64)
        #expect(mono.floatChannelData![0][10] == 0.5)
        #expect(AudioLevel.rmsDB(of: mono) > -7)
    }

    @Test func converterResamples() throws {
        let input = try buffer(frames: 4800, sampleRate: 48_000) { Float(sin(Double($0) * 0.1)) }
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try #require(PCMConverter(from: input.format, to: target))
        // The first call loses a little to resampler priming; steady state is exact.
        let first = try #require(converter.convert(input))
        let second = try #require(converter.convert(input))
        #expect(first.format.sampleRate == 16_000)
        #expect(abs(Int(first.frameLength) - 1600) <= 300)
        #expect(abs(Int(second.frameLength) - 1600) <= 64)
    }
}

@Suite("Rolling session policy")
struct RolloverTests {
    @Test func rollsOverAfterSilenceFollowingSpeech() {
        let policy = PolicyBox()
        #expect(!policy.ingest(duration: 0.5, levelDB: -20))
        #expect(!policy.ingest(duration: 0.5, levelDB: -80))
        #expect(policy.ingest(duration: 0.6, levelDB: -80))
    }

    @Test func leadingSilenceDoesNotRollOver() {
        let policy = PolicyBox()
        for _ in 0..<20 { #expect(!policy.ingest(duration: 0.5, levelDB: -90)) }
    }

    @Test func rollsOverAtMaxDurationEvenWhileTalking() {
        let policy = PolicyBox()
        var rolled = false
        for _ in 0..<100 where !rolled { rolled = policy.ingest(duration: 0.5, levelDB: -20) }
        #expect(rolled)
        #expect(policy.elapsed >= 50 && policy.elapsed < 51)
    }

    @Test func resetStartsFreshSession() {
        let policy = PolicyBox()
        _ = policy.ingest(duration: 49.9, levelDB: -20)
        policy.reset()
        #expect(!policy.ingest(duration: 1, levelDB: -20))
        #expect(policy.elapsed == 1)
    }
}

@Suite("Script recorder")
struct ScriptRecorderTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ieum-cli-tests-\(UUID().uuidString)")
    }

    @Test func writesTimestampedFinalsOnly() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US", startedAt: sampleDate, timeZone: utc)
        recorder.append(event("partial text", final: false))
        recorder.append(event("  Hello world.  ", final: true))
        recorder.append(event("   ", final: true))
        recorder.append(event("안녕하세요", final: true))
        let text = try String(contentsOf: recorder.fileURL, encoding: .utf8)
        #expect(text == "# Transcript (en-US) started 2024-05-06 07:08:09\n[07:08:09] Hello world.\n[07:08:09] 안녕하세요\n")
        #expect(recorder.fileURL.lastPathComponent == "transcript-2024-05-06_070809-en-US.txt")
    }

    @Test func eachSessionGetsANewFileAndNeverOverwrites() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try ScriptRecorder(directory: dir, locale: "ko-KR", startedAt: sampleDate, timeZone: utc)
        first.append(event("첫 번째", final: true))
        let second = try ScriptRecorder(directory: dir, locale: "ko-KR", startedAt: sampleDate, timeZone: utc)
        second.append(event("두 번째", final: true))
        #expect(first.fileURL != second.fileURL)
        #expect(try String(contentsOf: first.fileURL, encoding: .utf8).contains("첫 번째"))
        #expect(!(try String(contentsOf: first.fileURL, encoding: .utf8)).contains("두 번째"))
    }

    @Test func aSessionThatHearsNothingLeavesNoFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US", startedAt: sampleDate, timeZone: utc)
        recorder.append(event("only an interim", final: false))
        recorder.append(event("   ", final: true))
        recorder.close()
        #expect(!FileManager.default.fileExists(atPath: recorder.fileURL.path))
    }

    @Test func anUnwritableFolderFailsAtStartNotAtTheFirstSentence() {
        #expect(throws: (any Error).self) {
            _ = try ScriptRecorder(directory: URL(fileURLWithPath: "/System/not-writable-\(UUID().uuidString)"), locale: "en-US")
        }
    }

    @Test func linesAreOnDiskBeforeClose() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-AU", startedAt: sampleDate, timeZone: utc)
        recorder.append(event("durable", final: true))
        // Read through a separate handle without closing the recorder: simulates a crash right after the write.
        #expect(try String(contentsOf: recorder.fileURL, encoding: .utf8).contains("durable"))
    }

    @Test func appendAfterCloseIsIgnored() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US", startedAt: sampleDate, timeZone: utc)
        recorder.append(event("early", final: true))
        recorder.close()
        recorder.close()
        recorder.append(event("late", final: true))
        let text = try String(contentsOf: recorder.fileURL, encoding: .utf8)
        #expect(text.contains("early") && !text.contains("late"))
    }

    @Test func createsMissingDirectory() throws {
        let dir = tempDir().appendingPathComponent("nested/deeper")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent()) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US")
        #expect(FileManager.default.fileExists(atPath: dir.path))
        recorder.append(event("hello", final: true))
        #expect(FileManager.default.fileExists(atPath: recorder.fileURL.path))
    }
}

@Suite("Microphone device lookup")
struct DeviceLookupTests {
    private func defaultInputUID() -> (AudioDeviceID, String)? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return nil }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr, let uid else { return nil }
        return (device, uid.takeRetainedValue() as String)
    }

    @Test func defaultInputDeviceUIDRoundTrips() throws {
        let (device, uid) = try #require(defaultInputUID(), "no default input device on this machine")
        #expect(MicrophoneCapture.deviceID(forUID: uid) == device)
    }

    @Test func unknownUIDResolvesToNil() {
        #expect(MicrophoneCapture.deviceID(forUID: "no-such-device-uid") == nil)
    }

    @Test func unknownUIDFailsWithClearErrorBeforeCapturing() async {
        let capture = MicrophoneCapture(deviceUID: "no-such-device-uid")
        do {
            _ = try await capture.start()
            Issue.record("expected start() to throw")
        } catch let error as EngineError {
            // Permission may be denied in a headless test run; either way the failure must be a clear EngineError.
            #expect(!(error.errorDescription ?? "").isEmpty)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}

@Suite("Script detection")
struct TextScriptTests {
    @Test func hangulRatioOfPureKoreanIsOne() {
        #expect(TextScript.hangulRatio("안녕하세요, 오늘 회의를 시작하겠습니다.") == 1)
    }

    @Test func hangulRatioOfEnglishIsZero() {
        #expect(TextScript.hangulRatio("Hello, this is a test.") == 0)
    }

    @Test func mixedTextUsesTheLetterShare() {
        // 4 Hangul letters out of 10 letters.
        #expect(abs(TextScript.hangulRatio("예산 budget 검토") - 0.4) < 1e-9)
    }

    @Test func noLettersMeansZero() {
        #expect(TextScript.hangulRatio("123 … !") == 0)
        #expect(TextScript.hangulRatio("") == 0)
    }
}
