import Foundation

/// A language Ieum can recognize and translate. The raw value is the language code used in transcript events and by the translators.
public enum SpokenLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case chinese = "zh"

    public var code: String { rawValue }

    /// The locale recognized for this language. English is the exception: the user picks the accent.
    public var defaultLocale: String {
        switch self {
        case .english: "en-US"
        case .korean: "ko-KR"
        case .japanese: "ja-JP"
        case .chinese: "zh-CN"
        }
    }

    /// The language identifier Apple Translation uses.
    public var translationIdentifier: String { self == .chinese ? "zh-Hans" : rawValue }

    /// Whether words are separated by spaces. Japanese and Chinese run together, so pieces of one sentence are joined without a space.
    public var separatesWordsWithSpaces: Bool { self != .japanese && self != .chinese }

    public init?(code: String) {
        self.init(rawValue: String(code.prefix(2)).lowercased())
    }
}

/// The two languages a meeting is held in. The presets are the ones people actually need; one setting picks one of them.
/// The order is the order the modes list them in: the first language is the one the user is likelier to speak.
public enum LanguagePair: String, CaseIterable, Sendable {
    case koreanEnglish
    case koreanJapanese
    case koreanChinese
    case englishJapanese
    case englishChinese

    public var first: SpokenLanguage {
        switch self {
        case .koreanEnglish, .koreanJapanese, .koreanChinese: .korean
        case .englishJapanese, .englishChinese: .english
        }
    }

    public var second: SpokenLanguage {
        switch self {
        case .koreanEnglish: .english
        case .koreanJapanese, .englishJapanese: .japanese
        case .koreanChinese, .englishChinese: .chinese
        }
    }

    public var languages: [SpokenLanguage] { [first, second] }
    public var includesEnglish: Bool { languages.contains(.english) }

    public func other(than language: SpokenLanguage) -> SpokenLanguage { language == first ? second : first }
}

/// What the user is doing in the meeting. It decides which languages are recognized and which way they are translated.
/// The cases are in the order the user sees them; "first" and "second" are the two languages of the `LanguagePair`.
public enum MeetingMode: String, CaseIterable, Sendable {
    /// The other side speaks the first language; show the second.
    case firstToSecond
    /// The other side speaks the second language; show the first.
    case secondToFirst
    /// First-language captions, no translation.
    case firstCaptions
    /// Second-language captions, no translation.
    case secondCaptions
    /// Both sides speak. Each utterance is recognized in whichever language was spoken and translated to the other.
    case conversation

    public var isConversation: Bool { self == .conversation }
    /// Conversation mode runs two recognizers of the newer kind, so it needs macOS 26.
    public var isAvailableOnThisMac: Bool { self != .conversation || ModernSpeechSupport.isAvailable }
    public func translates(in pair: LanguagePair) -> Bool { !translationPairs(in: pair).isEmpty }

    /// The language of the speech that is recognized, or both languages in conversation mode (English first when it is one of them).
    public func recognizedLanguages(in pair: LanguagePair) -> [SpokenLanguage] {
        switch self {
        case .firstToSecond, .firstCaptions: [pair.first]
        case .secondToFirst, .secondCaptions: [pair.second]
        case .conversation: pair.second == .english ? [pair.second, pair.first] : [pair.first, pair.second]
        }
    }

    /// Whether English speech is recognized in this mode, which is when the accent choice matters.
    public func recognizesEnglish(in pair: LanguagePair) -> Bool { recognizedLanguages(in: pair).contains(.english) }

    /// Locales to recognize. Conversation mode returns both, English first when it is one of them.
    public func recognitionLocales(in pair: LanguagePair, englishLocale: String) -> [String] {
        recognizedLanguages(in: pair).map { $0 == .english ? englishLocale : $0.defaultLocale }
    }

    /// The language code to translate speech in `language` ("en", "ko", "ja", "zh") into, or nil when it is not translated.
    public func translationTarget(forSpeechIn language: String, in pair: LanguagePair) -> String? {
        guard translates(in: pair), let spoken = SpokenLanguage(code: language), recognizedLanguages(in: pair).contains(spoken) else { return nil }
        return pair.other(than: spoken).code
    }

    /// Every (source, target) translator this mode needs.
    public func translationPairs(in pair: LanguagePair) -> [(source: String, target: String)] {
        switch self {
        case .firstCaptions, .secondCaptions: []
        case .firstToSecond: [(pair.first.code, pair.second.code)]
        case .secondToFirst: [(pair.second.code, pair.first.code)]
        case .conversation: recognizedLanguages(in: pair).map { ($0.code, pair.other(than: $0).code) }
        }
    }

    /// The other direction with the same kind of output, for the swap shortcut. Conversation has no direction, so it picks one.
    public var swappedDirection: MeetingMode {
        switch self {
        case .firstToSecond: .secondToFirst
        case .secondToFirst, .conversation: .firstToSecond
        case .firstCaptions: .secondCaptions
        case .secondCaptions: .firstCaptions
        }
    }

    /// The mode a setting saved by an earlier version stands for. Until the language pair existed the first language was
    /// Korean and the second English; "captionsOnly" used to depend on a separate caption language.
    public static func migrated(raw: String, legacyCaptionLanguage: String?) -> MeetingMode? {
        switch raw {
        case "koreanToEnglish": return .firstToSecond
        case "englishToKorean": return .secondToFirst
        case "koreanCaptions": return .firstCaptions
        case "englishCaptions": return .secondCaptions
        case "captionsOnly": return (legacyCaptionLanguage ?? "").hasPrefix("ko") ? .firstCaptions : .secondCaptions
        default: return MeetingMode(rawValue: raw)
        }
    }
}
