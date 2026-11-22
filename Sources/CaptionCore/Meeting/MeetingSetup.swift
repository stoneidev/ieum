import Foundation

/// A language Ieum can recognize and translate. The raw value is the language code used in transcript events and by the translators.
public enum SpokenLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case chinese = "zh"

    public var code: String { rawValue }

    /// The language most people who speak this one want to read it in: Korean for everyone else, English for Korean.
    public var defaultCounterpart: SpokenLanguage { self == .korean ? .english : .korean }

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

/// What the user wants from a meeting: which language the other side speaks, which language to read, and whether both sides
/// speak. Any two of the languages work together, so this is chosen with two pickers and one switch instead of a list of modes.
public struct MeetingSetup: Equatable, Sendable {
    /// The language that is recognized.
    public private(set) var heard: SpokenLanguage
    /// The language the speech is translated into; nil shows captions only.
    public private(set) var shown: SpokenLanguage?
    /// Both languages are spoken: each sentence is recognized in whichever one it was said in and translated into the other.
    public private(set) var bothWays: Bool

    public init(heard: SpokenLanguage, shown: SpokenLanguage?, bothWays: Bool = false) {
        self.heard = heard
        self.shown = shown == heard ? nil : shown
        self.bothWays = bothWays && self.shown != nil
    }

    public var translates: Bool { shown != nil }
    public var isConversation: Bool { bothWays }
    /// Detecting the language per sentence runs two recognizers of the newer kind, so it needs macOS 26.
    public static var bothWaysIsAvailableOnThisMac: Bool { ModernSpeechSupport.isAvailable }

    // MARK: Choosing

    /// Picking the language that is already shown swaps the two, so the choice never ends in two equal languages.
    public func hearing(_ language: SpokenLanguage) -> MeetingSetup {
        MeetingSetup(heard: language, shown: shown == language ? heard : shown, bothWays: bothWays)
    }

    public func showing(_ language: SpokenLanguage?) -> MeetingSetup {
        language == heard
            ? MeetingSetup(heard: shown ?? heard, shown: heard, bothWays: bothWays)
            : MeetingSetup(heard: heard, shown: language, bothWays: bothWays)
    }

    /// Switches translation on or off with one choice. Turning it on picks the language to read: the one used last if there is
    /// one, else the usual partner of the spoken language. Turning it off keeps the spoken language and shows captions only.
    public func translating(_ on: Bool, preferred: SpokenLanguage? = nil) -> MeetingSetup {
        guard on != translates else { return self }
        guard on else { return MeetingSetup(heard: heard, shown: nil) }
        let target = [preferred, heard.defaultCounterpart].compactMap { $0 }.first { $0 != heard } ?? heard.defaultCounterpart
        return MeetingSetup(heard: heard, shown: target, bothWays: bothWays)
    }

    public func speakingBothWays(_ on: Bool) -> MeetingSetup { MeetingSetup(heard: heard, shown: shown, bothWays: on) }

    /// The other direction. Without a translation there is nothing to swap, so captions move on to the next language.
    public var swapped: MeetingSetup {
        if let shown { return MeetingSetup(heard: shown, shown: heard, bothWays: bothWays) }
        let all = SpokenLanguage.allCases
        let next = all[((all.firstIndex(of: heard) ?? 0) + 1) % all.count]
        return MeetingSetup(heard: next, shown: nil)
    }

    // MARK: What the engines need

    /// The languages recognized: one, or both in conversation (English first when it is one of them).
    public var recognizedLanguages: [SpokenLanguage] {
        guard bothWays, let shown else { return [heard] }
        return shown == .english ? [shown, heard] : [heard, shown]
    }

    /// Whether a running session can carry on when the setup changes from `other` to this one: the same languages are
    /// recognized and translated, only the order of the two is different (swapping in the both-ways case).
    public func runsLike(_ other: MeetingSetup) -> Bool {
        func key(_ setup: MeetingSetup) -> [String] { setup.recognizedLanguages.map(\.code) + setup.translationPairs.map { "\($0.source)>\($0.target)" } }
        return Set(key(self)) == Set(key(other))
    }

    /// Whether English speech is recognized, which is when the accent choice matters.
    public var recognizesEnglish: Bool { recognizedLanguages.contains(.english) }
    public var involvesEnglish: Bool { heard == .english || shown == .english }

    public func recognitionLocales(englishLocale: String) -> [String] {
        recognizedLanguages.map { $0 == .english ? englishLocale : $0.defaultLocale }
    }

    /// The language code to translate speech in `language` ("en", "ko", "ja", "zh") into, or nil when it is not translated.
    public func translationTarget(forSpeechIn language: String) -> String? {
        guard let shown, let spoken = SpokenLanguage(code: language) else { return nil }
        if spoken == heard { return shown.code }
        return bothWays && spoken == shown ? heard.code : nil
    }

    /// Every (source, target) translator this setup needs.
    public var translationPairs: [(source: String, target: String)] {
        guard let shown else { return [] }
        return recognizedLanguages.map { ($0.code, ($0 == heard ? shown : heard).code) }
    }

    // MARK: Settings saved by earlier versions

    /// The setup a "meetingMode" saved before languages could be chosen stands for. Back then the languages were English and
    /// Korean, and "captionsOnly" depended on a separate caption language.
    public static func migrated(mode raw: String, legacyCaptionLanguage: String?) -> MeetingSetup? {
        switch raw {
        case "koreanToEnglish": MeetingSetup(heard: .korean, shown: .english)
        case "englishToKorean": MeetingSetup(heard: .english, shown: .korean)
        case "koreanCaptions": MeetingSetup(heard: .korean, shown: nil)
        case "englishCaptions": MeetingSetup(heard: .english, shown: nil)
        case "conversation": MeetingSetup(heard: .english, shown: .korean, bothWays: true)
        case "captionsOnly": MeetingSetup(heard: (legacyCaptionLanguage ?? "").hasPrefix("ko") ? .korean : .english, shown: nil)
        default: nil
        }
    }
}
