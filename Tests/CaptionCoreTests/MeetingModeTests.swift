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

    @Test func plainScriptsStayUntagged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = try ScriptRecorder(directory: dir, locale: "en-US", timeZone: TimeZone(identifier: "UTC")!)
        recorder.append(TranscriptionEvent(text: "Hello", isFinal: true, locale: "en-US"))
        let text = try String(contentsOf: recorder.fileURL, encoding: .utf8)
        #expect(!text.contains("[EN]"))
    }
}
