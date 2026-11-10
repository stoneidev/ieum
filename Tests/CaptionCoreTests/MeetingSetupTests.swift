import Foundation
import Testing

@testable import CaptionCore

@Suite("Meeting setup")
struct MeetingSetupTests {
    private let enKo = MeetingSetup(heard: .english, shown: .korean)

    @Test func translatesOnlyWhatIsHeard() {
        #expect(enKo.translationTarget(forSpeechIn: "en") == "ko")
        #expect(enKo.translationTarget(forSpeechIn: "ko") == nil)
        #expect(enKo.translationPairs.map { "\($0.source)>\($0.target)" } == ["en>ko"])
        #expect(enKo.recognitionLocales(englishLocale: "en-AU") == ["en-AU"])
    }

    @Test func bothWaysTranslatesEachLanguageIntoTheOther() {
        let both = enKo.speakingBothWays(true)
        #expect(both.isConversation)
        #expect(both.translationTarget(forSpeechIn: "en") == "ko" && both.translationTarget(forSpeechIn: "ko") == "en")
        #expect(both.translationTarget(forSpeechIn: "ja") == nil)
        #expect(both.translationPairs.map { "\($0.source)>\($0.target)" } == ["en>ko", "ko>en"])
        #expect(both.recognitionLocales(englishLocale: "en-US") == ["en-US", "ko-KR"])
    }

    @Test func englishIsListedFirstAndEveryOtherPairKeepsItsOrder() {
        #expect(MeetingSetup(heard: .korean, shown: .english, bothWays: true).recognizedLanguages == [.english, .korean])
        #expect(MeetingSetup(heard: .korean, shown: .japanese, bothWays: true).recognitionLocales(englishLocale: "en-US") == ["ko-KR", "ja-JP"])
        #expect(MeetingSetup(heard: .japanese, shown: .chinese, bothWays: true).recognitionLocales(englishLocale: "en-US") == ["ja-JP", "zh-CN"])
        #expect(MeetingSetup(heard: .chinese, shown: .english, bothWays: true).translationPairs.map { "\($0.source)>\($0.target)" } == ["en>zh", "zh>en"])
    }

    @Test func captionsNeverTranslate() {
        for language in SpokenLanguage.allCases {
            let captions = MeetingSetup(heard: language, shown: nil, bothWays: true)
            #expect(!captions.translates && !captions.isConversation && captions.translationPairs.isEmpty)
            #expect(captions.recognizedLanguages == [language])
            for spoken in SpokenLanguage.allCases { #expect(captions.translationTarget(forSpeechIn: spoken.code) == nil) }
        }
    }

    @Test func anyTwoDifferentLanguagesWork() {
        for heard in SpokenLanguage.allCases {
            for shown in SpokenLanguage.allCases where shown != heard {
                let setup = MeetingSetup(heard: heard, shown: shown)
                #expect(setup.translationTarget(forSpeechIn: heard.code) == shown.code)
                #expect(setup.recognitionLocales(englishLocale: "en-AU").count == 1)
            }
        }
    }

    @Test func theSameLanguageTwiceIsNeverKept() {
        #expect(MeetingSetup(heard: .korean, shown: .korean).shown == nil)
        // Choosing the language that is already shown swaps the two instead.
        let swapped = enKo.hearing(.korean)
        #expect(swapped.heard == .korean && swapped.shown == .english)
        let other = enKo.showing(.english)
        #expect(other.heard == .korean && other.shown == .english)
        #expect(enKo.showing(.japanese).heard == .english && enKo.showing(.japanese).shown == .japanese)
        // Turning the translation off also turns the two-way switch off.
        #expect(!enKo.speakingBothWays(true).showing(nil).bothWays)
    }

    @Test func swappingComesBackAndKeepsTheSwitch() {
        #expect(enKo.swapped.swapped == enKo)
        #expect(enKo.speakingBothWays(true).swapped.bothWays)
        let captions = MeetingSetup(heard: .english, shown: nil)
        #expect(captions.swapped.heard == .korean && captions.swapped.shown == nil)
    }

    @Test func englishAccentOnlyMattersWhenEnglishIsRecognized() {
        #expect(enKo.recognizesEnglish && !MeetingSetup(heard: .korean, shown: .english).recognizesEnglish)
        #expect(MeetingSetup(heard: .korean, shown: .english, bothWays: true).recognizesEnglish)
        #expect(MeetingSetup(heard: .korean, shown: .english).involvesEnglish)
    }

    @Test func earlierSettingsBecomeTheMatchingSetup() {
        #expect(MeetingSetup.migrated(mode: "koreanToEnglish", legacyCaptionLanguage: nil) == MeetingSetup(heard: .korean, shown: .english))
        #expect(MeetingSetup.migrated(mode: "englishToKorean", legacyCaptionLanguage: nil) == enKo)
        #expect(MeetingSetup.migrated(mode: "koreanCaptions", legacyCaptionLanguage: nil) == MeetingSetup(heard: .korean, shown: nil))
        #expect(MeetingSetup.migrated(mode: "englishCaptions", legacyCaptionLanguage: nil) == MeetingSetup(heard: .english, shown: nil))
        #expect(MeetingSetup.migrated(mode: "conversation", legacyCaptionLanguage: nil) == enKo.speakingBothWays(true))
        #expect(MeetingSetup.migrated(mode: "captionsOnly", legacyCaptionLanguage: "ko-KR") == MeetingSetup(heard: .korean, shown: nil))
        #expect(MeetingSetup.migrated(mode: "captionsOnly", legacyCaptionLanguage: nil) == MeetingSetup(heard: .english, shown: nil))
        #expect(MeetingSetup.migrated(mode: "nonsense", legacyCaptionLanguage: nil) == nil)
    }
}

@Suite("Spoken languages")
struct SpokenLanguageTests {
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
