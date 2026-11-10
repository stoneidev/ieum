import Foundation
import Testing

@testable import CaptionCore

@Suite("Meeting mode")
struct MeetingModeTests {
    private let koEn = LanguagePair.koreanEnglish

    @Test func secondToFirstTranslatesOnlyTheSecondLanguage() {
        #expect(MeetingMode.secondToFirst.translationTarget(forSpeechIn: "en", in: koEn) == "ko")
        #expect(MeetingMode.secondToFirst.translationTarget(forSpeechIn: "ko", in: koEn) == nil)
    }

    @Test func firstToSecondTranslatesOnlyTheFirstLanguage() {
        #expect(MeetingMode.firstToSecond.translationTarget(forSpeechIn: "ko", in: koEn) == "en")
        #expect(MeetingMode.firstToSecond.translationTarget(forSpeechIn: "en", in: koEn) == nil)
    }

    @Test func conversationTranslatesBothWaysAndNothingElse() {
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "en", in: koEn) == "ko")
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "ko", in: koEn) == "en")
        #expect(MeetingMode.conversation.translationTarget(forSpeechIn: "ja", in: koEn) == nil)
    }

    @Test func captionModesNeverTranslate() {
        for pair in LanguagePair.allCases {
            for mode in [MeetingMode.firstCaptions, .secondCaptions] {
                for language in SpokenLanguage.allCases {
                    #expect(mode.translationTarget(forSpeechIn: language.code, in: pair) == nil)
                }
                #expect(!mode.translates(in: pair))
                #expect(mode.translationPairs(in: pair).isEmpty)
            }
            #expect(MeetingMode.conversation.translates(in: pair) && MeetingMode.secondToFirst.translates(in: pair))
        }
    }

    @Test func theModeNamesTheLanguageThatIsRecognized() {
        #expect(MeetingMode.firstCaptions.recognitionLocales(in: koEn, englishLocale: "en-AU") == ["ko-KR"])
        #expect(MeetingMode.secondCaptions.recognitionLocales(in: koEn, englishLocale: "en-AU") == ["en-AU"])
        #expect(MeetingMode.secondCaptions.recognizesEnglish(in: koEn) && !MeetingMode.firstCaptions.recognizesEnglish(in: koEn))
        #expect(!MeetingMode.firstToSecond.recognizesEnglish(in: koEn) && MeetingMode.conversation.recognizesEnglish(in: koEn))
    }

    @Test func earlierSettingsBecomeTheMatchingModeOfTheKoreanEnglishPair() {
        #expect(MeetingMode.migrated(raw: "koreanToEnglish", legacyCaptionLanguage: nil) == .firstToSecond)
        #expect(MeetingMode.migrated(raw: "englishToKorean", legacyCaptionLanguage: nil) == .secondToFirst)
        #expect(MeetingMode.migrated(raw: "koreanCaptions", legacyCaptionLanguage: nil) == .firstCaptions)
        #expect(MeetingMode.migrated(raw: "englishCaptions", legacyCaptionLanguage: nil) == .secondCaptions)
        #expect(MeetingMode.migrated(raw: "captionsOnly", legacyCaptionLanguage: "ko-KR") == .firstCaptions)
        #expect(MeetingMode.migrated(raw: "captionsOnly", legacyCaptionLanguage: "en-AU") == .secondCaptions)
        #expect(MeetingMode.migrated(raw: "captionsOnly", legacyCaptionLanguage: nil) == .secondCaptions)
        #expect(MeetingMode.migrated(raw: "conversation", legacyCaptionLanguage: "ko-KR") == .conversation)
        #expect(MeetingMode.migrated(raw: "secondToFirst", legacyCaptionLanguage: nil) == .secondToFirst)
        #expect(MeetingMode.migrated(raw: "nonsense", legacyCaptionLanguage: nil) == nil)
    }

    @Test func recognitionLocalesFollowTheModeAndThePair() {
        #expect(MeetingMode.secondToFirst.recognitionLocales(in: koEn, englishLocale: "en-AU") == ["en-AU"])
        #expect(MeetingMode.firstToSecond.recognitionLocales(in: koEn, englishLocale: "en-AU") == ["ko-KR"])
        #expect(MeetingMode.conversation.recognitionLocales(in: koEn, englishLocale: "en-AU") == ["en-AU", "ko-KR"])
        #expect(MeetingMode.firstToSecond.recognitionLocales(in: .koreanJapanese, englishLocale: "en-AU") == ["ko-KR"])
        #expect(MeetingMode.secondToFirst.recognitionLocales(in: .koreanJapanese, englishLocale: "en-AU") == ["ja-JP"])
        #expect(MeetingMode.firstCaptions.recognitionLocales(in: .englishChinese, englishLocale: "en-AU") == ["en-AU"])
        #expect(MeetingMode.conversation.recognitionLocales(in: .englishChinese, englishLocale: "en-US") == ["en-US", "zh-CN"])
        #expect(MeetingMode.conversation.recognitionLocales(in: .koreanChinese, englishLocale: "en-US") == ["ko-KR", "zh-CN"])
    }

    @Test func translatorsNeededMatchTheDirections() {
        func names(_ mode: MeetingMode, _ pair: LanguagePair) -> [String] { mode.translationPairs(in: pair).map { "\($0.source)>\($0.target)" } }
        #expect(names(.conversation, koEn) == ["en>ko", "ko>en"])
        #expect(names(.secondToFirst, koEn) == ["en>ko"])
        #expect(names(.firstToSecond, .koreanJapanese) == ["ko>ja"])
        #expect(names(.conversation, .englishChinese) == ["en>zh", "zh>en"])
        #expect(MeetingMode.conversation.isConversation && !MeetingMode.secondToFirst.isConversation)
    }

    @Test func swappingTheDirectionComesBack() {
        for mode in [MeetingMode.firstToSecond, .secondToFirst, .firstCaptions, .secondCaptions] {
            #expect(mode.swappedDirection.swappedDirection == mode)
        }
        #expect(MeetingMode.conversation.swappedDirection == .firstToSecond)
    }

    @Test func everyModeHasADistinctRawValue() {
        #expect(Set(MeetingMode.allCases.map(\.rawValue)).count == MeetingMode.allCases.count)
    }
}

@Suite("Language pairs")
struct LanguagePairTests {
    @Test func everyPresetHasTwoDifferentLanguages() {
        for pair in LanguagePair.allCases { #expect(pair.first != pair.second) }
        #expect(Set(LanguagePair.allCases.map(\.rawValue)).count == LanguagePair.allCases.count)
    }

    @Test func koreanEnglishKeepsTheOrderTheModesAlwaysHad() {
        #expect(LanguagePair.koreanEnglish.first == .korean && LanguagePair.koreanEnglish.second == .english)
        #expect(LanguagePair.englishJapanese.second == .japanese && LanguagePair.englishChinese.second == .chinese)
    }

    @Test func languageCodesAndLocalesAreSpelledTheWayTheFrameworksExpectThem() {
        #expect(SpokenLanguage(code: "ja-JP") == .japanese && SpokenLanguage(code: "zh") == .chinese && SpokenLanguage(code: "xx") == nil)
        #expect(SpokenLanguage.chinese.translationIdentifier == "zh-Hans" && SpokenLanguage.korean.translationIdentifier == "ko")
        #expect(SpokenLanguage.allCases.map(\.defaultLocale) == ["en-US", "ko-KR", "ja-JP", "zh-CN"])
    }

    @Test func piecesOfJapaneseAndChineseAreJoinedWithoutASpace() {
        #expect(TextScript.joiner(between: "予算は", and: "確認します") == "")
        #expect(TextScript.joiner(between: "预算", and: "已确认") == "")
        #expect(TextScript.joiner(between: "예산은", and: "확인합니다") == " ")
        #expect(TextScript.joiner(between: "The budget", and: "is final") == " ")
        #expect(TextScript.joiner(between: "", and: "text") == "")
    }

    @Test func sentencesAreJoinedTheWayTheirScriptNeedsIt() {
        #expect(TextScript.join(["予算は確定です。", "明日共有します。"]) == "予算は確定です。明日共有します。")
        #expect(TextScript.join(["예산은 확정입니다.", "내일 공유합니다."]) == "예산은 확정입니다. 내일 공유합니다.")
        #expect(TextScript.join(["Budget is final.", "", "Share tomorrow."]) == "Budget is final. Share tomorrow.")
        #expect(TextScript.join([]) == "")
    }

    @Test func wideScriptsAreRecognizedByTheirLetters() {
        #expect(TextScript.cjkRatio("予算は確認します") > 0.9)
        #expect(TextScript.cjkRatio("预算已确认") > 0.9)
        #expect(TextScript.cjkRatio("예산은 확인합니다") > 0.9)
        #expect(TextScript.cjkRatio("The budget is final") == 0)
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
