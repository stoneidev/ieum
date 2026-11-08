import Foundation
import Testing

@testable import IeumCore

@Suite("Meeting mode")
struct MeetingModeTests {
    @Test func englishToKoreanTranslatesOnlyEnglish() {
        #expect(MeetingMode.englishToKorean.translationTarget(forSpeechIn: "en") == "ko")
        #expect(MeetingMode.englishToKorean.translationTarget(forSpeechIn: "ko") == nil)
    }

    @Test func koreanToEnglishTranslatesOnlyKorean() {
        #expect(MeetingMode.koreanToEnglish.translationTarget(forSpeechIn: "ko") == "en")
        #expect(MeetingMode.koreanToEnglish.translationTarget(forSpeechIn: "en") == nil)
    }

    @Test func conversationTranslatesBothWaysAndNothingElse() {
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "en") == "ko")
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "ko") == "en")
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "ja") == nil)
    }

    @Test func captionsOnlyNeverTranslates() {
        #expect(MeetingMode.captionsOnly.translationTarget(forSpeechIn: "en") == nil)
        #expect(!MeetingMode.captionsOnly.translates)
        #expect(MeetingMode.captionsOnly.translationPairs.isEmpty)
    }

    @Test func recognitionLocalesFollowTheMode() {
        #expect(MeetingMode.englishToKorean.recognitionLocales(englishLocale: "en-AU", captionLocale: "ko-KR") == ["en-AU"])
        #expect(MeetingMode.koreanToEnglish.recognitionLocales(englishLocale: "en-AU", captionLocale: "en-US") == ["ko-KR"])
        #expect(MeetingMode.conversation.recognitionLocales(englishLocale: "en-AU", captionLocale: "en-US") == ["en-AU", "ko-KR"])
        #expect(MeetingMode.captionsOnly.recognitionLocales(englishLocale: "en-AU", captionLocale: "en-US") == ["en-US"])
    }

    @Test func translatorsNeededMatchTheDirections() {
        #expect(MeetingMode.conversation.translationPairs.map { "\($0.source)>\($0.target)" } == ["en>ko", "ko>en"])
        #expect(MeetingMode.englishToKorean.translationPairs.map { "\($0.source)>\($0.target)" } == ["en>ko"])
        #expect(MeetingMode.conversation.isConversation && !MeetingMode.englishToKorean.isConversation)
    }

    @Test func everyModeHasADistinctRawValue() {
        #expect(Set(MeetingMode.allCases.map(\.rawValue)).count == MeetingMode.allCases.count)
    }
}

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
