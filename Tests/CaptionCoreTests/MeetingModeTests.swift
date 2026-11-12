import Foundation
import Testing

@testable import CaptionCore

@Suite("Script language tags")
struct ScriptLanguageTagTests {
    @Test func conversationScriptsTagEachLineWithItsLanguage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let utc = TimeZone(identifier: "UTC")!
        let recorder = try ScriptRecorder(directory: dir, locale: "conversation", startedAt: Date(timeIntervalSince1970: 1_714_979_289), timeZone: utc, tagLanguages: true)
        let at = Date(timeIntervalSince1970: 1_714_979_289)
        recorder.append(TranscriptionEvent(text: "Hello there", isFinal: true, locale: "en-US", timestamp: at))
        recorder.appendTranslation("안녕하세요", forSentenceAt: at, targetLanguage: "ko-KR")
        recorder.append(TranscriptionEvent(text: "네, 안녕하세요", isFinal: true, locale: "ko-KR", timestamp: at))
        let lines = try String(contentsOf: recorder.fileURL, encoding: .utf8).split(separator: "\n").dropFirst().map(String.init)
        #expect(lines == ["[07:08:09] [EN] Hello there", "[07:08:09] [KO] → 안녕하세요", "[07:08:09] [KO] 네, 안녕하세요"])
    }

    @Test func callScriptsTagEachLineWithItsSpeaker() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let utc = TimeZone(identifier: "UTC")!
        let recorder = try ScriptRecorder(directory: dir, locale: "call", startedAt: Date(timeIntervalSince1970: 1_714_979_289), timeZone: utc, tagSpeakers: true)
        let at = Date(timeIntervalSince1970: 1_714_979_289)
        recorder.append(TranscriptionEvent(text: "来週から始めます", isFinal: true, locale: "ja-JP", timestamp: at, speaker: .them))
        recorder.appendTranslation("다음 주부터 시작합니다", forSentenceAt: at, targetLanguage: "ko", speaker: .them)
        recorder.append(TranscriptionEvent(text: "네, 알겠습니다", isFinal: true, locale: "ko-KR", timestamp: at, speaker: .me))
        let lines = try String(contentsOf: recorder.fileURL, encoding: .utf8).split(separator: "\n").dropFirst().map(String.init)
        #expect(lines == ["[07:08:09] [THEM] 来週から始めます", "[07:08:09] [THEM] → 다음 주부터 시작합니다", "[07:08:09] [ME] 네, 알겠습니다"])
        let script = ScriptParser.parse(try String(contentsOf: recorder.fileURL, encoding: .utf8), timeZone: utc)
        #expect(script.entries.map(\.language) == ["them", "me"])
        #expect(script.entries[0].translation == "다음 주부터 시작합니다")
    }

    @Test func plainScriptsStayUntagged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US", timeZone: TimeZone(identifier: "UTC")!)
        recorder.append(TranscriptionEvent(text: "Hello", isFinal: true, locale: "en-US"))
        let text = try String(contentsOf: recorder.fileURL, encoding: .utf8)
        #expect(!text.contains("[EN]"))
    }
}
