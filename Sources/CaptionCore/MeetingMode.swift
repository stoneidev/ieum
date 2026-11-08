import Foundation

/// What the user is doing in the meeting. It decides which languages are recognized and which way they are translated.
/// The cases are in the order the user sees them.
public enum MeetingMode: String, CaseIterable, Sendable {
    /// The other side speaks Korean; show English.
    case koreanToEnglish
    /// The other side speaks English; show Korean.
    case englishToKorean
    /// Korean captions, no translation.
    case koreanCaptions
    /// English captions, no translation.
    case englishCaptions
    /// Both sides speak. Each utterance is recognized in whichever language was spoken and translated to the other.
    case conversation

    public var isConversation: Bool { self == .conversation }
    /// Conversation mode runs two recognizers of the newer kind, so it needs macOS 26.
    public var isAvailableOnThisMac: Bool { self != .conversation || ModernSpeechSupport.isAvailable }
    public var translates: Bool { !translationPairs.isEmpty }
    /// Whether English speech is recognized in this mode.
    public var recognizesEnglish: Bool { self != .koreanToEnglish && self != .koreanCaptions }

    /// Locales to recognize. Conversation mode returns both, the English locale first.
    public func recognitionLocales(englishLocale: String) -> [String] {
        switch self {
        case .englishToKorean, .englishCaptions: [englishLocale]
        case .koreanToEnglish, .koreanCaptions: ["ko-KR"]
        case .conversation: [englishLocale, "ko-KR"]
        }
    }

    /// The language code to translate speech in `language` ("en", "ko") into, or nil when it is not translated.
    public func translationTarget(forSpeechIn language: String) -> String? {
        switch self {
        case .koreanCaptions, .englishCaptions: nil
        case .englishToKorean: language == "en" ? "ko" : nil
        case .koreanToEnglish: language == "ko" ? "en" : nil
        case .conversation: language == "en" ? "ko" : (language == "ko" ? "en" : nil)
        }
    }

    /// Every (source, target) translator this mode needs.
    public var translationPairs: [(source: String, target: String)] {
        switch self {
        case .koreanCaptions, .englishCaptions: []
        case .englishToKorean: [("en", "ko")]
        case .koreanToEnglish: [("ko", "en")]
        case .conversation: [("en", "ko"), ("ko", "en")]
        }
    }

    /// The mode a setting saved by an older version stands for. "captionsOnly" used to depend on a separate caption
    /// language, which the new modes carry in their name.
    public static func migrated(raw: String, legacyCaptionLanguage: String?) -> MeetingMode? {
        if raw == "captionsOnly" { return (legacyCaptionLanguage ?? "").hasPrefix("ko") ? .koreanCaptions : .englishCaptions }
        return MeetingMode(rawValue: raw)
    }
}
