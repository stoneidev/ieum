import Foundation

/// What the user is doing in the meeting. It decides which languages are recognized and which way they are translated.
public enum MeetingMode: String, CaseIterable, Sendable {
    /// The other side speaks English; show Korean.
    case englishToKorean
    /// The other side speaks Korean; show English.
    case koreanToEnglish
    /// Both sides speak. Each utterance is recognized in whichever language was spoken and translated to the other.
    case conversation
    /// Captions in one language, no translation.
    case captionsOnly

    public var isConversation: Bool { self == .conversation }
    /// Conversation mode runs two recognizers of the newer kind, so it needs macOS 26.
    public var isAvailableOnThisMac: Bool { self != .conversation || ModernSpeechSupport.isAvailable }
    public var translates: Bool { self != .captionsOnly }

    /// Locales to recognize. Conversation mode returns both, the English locale first.
    public func recognitionLocales(englishLocale: String, captionLocale: String) -> [String] {
        switch self {
        case .englishToKorean: [englishLocale]
        case .koreanToEnglish: ["ko-KR"]
        case .conversation: [englishLocale, "ko-KR"]
        case .captionsOnly: [captionLocale]
        }
    }

    /// The language code to translate speech in `language` ("en", "ko") into, or nil when it is not translated.
    public func translationTarget(forSpeechIn language: String) -> String? {
        switch self {
        case .captionsOnly: nil
        case .englishToKorean: language == "en" ? "ko" : nil
        case .koreanToEnglish: language == "ko" ? "en" : nil
        case .conversation: language == "en" ? "ko" : (language == "ko" ? "en" : nil)
        }
    }

    /// Every (source, target) translator this mode needs.
    public var translationPairs: [(source: String, target: String)] {
        switch self {
        case .captionsOnly: []
        case .englishToKorean: [("en", "ko")]
        case .koreanToEnglish: [("ko", "en")]
        case .conversation: [("en", "ko"), ("ko", "en")]
        }
    }
}
