import Foundation
import CaptionCore

enum Language: String, CaseIterable {
    case englishUS = "en-US"
    case englishAU = "en-AU"
    case korean = "ko-KR"

    @MainActor var title: String {
        switch self {
        case .englishUS: tr("English (US)", "영어 (미국)")
        case .englishAU: tr("English (Australia)", "영어 (호주)")
        case .korean: "한국어"
        }
    }
}

enum Source: String, CaseIterable {
    case microphone
    case system

    @MainActor var title: String {
        self == .microphone ? tr("Microphone", "마이크") : tr("System audio", "시스템 소리")
    }
}

enum DisplayMode: String, CaseIterable {
    case bar
    case panel

    @MainActor var title: String {
        self == .bar ? tr("Subtitle bar", "자막 바") : tr("Transcript panel", "기록 패널")
    }
}

enum TextSize: String, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    var points: CGFloat {
        switch self {
        case .small: 22
        case .medium: 30
        case .large: 40
        case .extraLarge: 52
        }
    }

    @MainActor var title: String {
        switch self {
        case .small: tr("Small", "작게")
        case .medium: tr("Medium", "보통")
        case .large: tr("Large", "크게")
        case .extraLarge: tr("Extra large", "아주 크게")
        }
    }
}

enum BackgroundStyle: String, CaseIterable {
    case glass
    case solid
    case black
    case light

    @MainActor var title: String {
        switch self {
        case .glass: tr("Smoked glass", "스모크 유리")
        case .solid: tr("Solid dark", "진한 회색")
        case .black: tr("Black, white text", "검정 배경, 흰 글씨")
        case .light: tr("Light", "밝게")
        }
    }
}

enum TranslationLayout: String, CaseIterable {
    case both
    case translationOnly

    @MainActor var title: String {
        self == .both ? tr("Original and translation", "원문과 번역") : tr("Translation only", "번역만")
    }
}

extension SpokenLanguage {
    /// The name in the interface language: "Korean" / "한국어".
    @MainActor var name: String {
        switch self {
        case .english: tr("English", "영어")
        case .korean: tr("Korean", "한국어")
        case .japanese: tr("Japanese", "일본어")
        case .chinese: tr("Chinese", "중국어")
        }
    }

    /// The name in its own language, which is how people find their language in a list.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        case .japanese: "日本語"
        case .chinese: "中文"
        }
    }
}

extension LanguagePair {
    @MainActor var title: String { "\(first.nativeName) ↔ \(second.nativeName)" }
}

/// Names and explanations for the meeting modes. The rules live in `MeetingMode` (CaptionCore); the names follow the language pair.
extension MeetingMode {
    @MainActor func title(in pair: LanguagePair) -> String {
        let first = pair.first.name, second = pair.second.name
        switch self {
        case .firstToSecond: return tr("\(first) → \(second)", "\(first) → \(second)")
        case .secondToFirst: return tr("\(second) → \(first)", "\(second) → \(first)")
        case .firstCaptions: return tr("\(first) captions (no translation)", "\(first) 자막 (번역 없음)")
        case .secondCaptions: return tr("\(second) captions (no translation)", "\(second) 자막 (번역 없음)")
        case .conversation: return tr("Detect the language and translate", "언어 자동 인식 번역")
        }
    }

    /// The name for tight places such as the panel header; the full name says "(no translation)".
    @MainActor func shortTitle(in pair: LanguagePair) -> String {
        switch self {
        case .firstCaptions: tr("\(pair.first.name) captions", "\(pair.first.name) 자막")
        case .secondCaptions: tr("\(pair.second.name) captions", "\(pair.second.name) 자막")
        default: title(in: pair)
        }
    }

    @MainActor func explanation(in pair: LanguagePair) -> String {
        let first = pair.first.name, second = pair.second.name
        switch self {
        case .firstToSecond: return tr("The other person speaks \(first). You read \(second).", "상대가 \(first)로 말합니다. \(second) 자막으로 봅니다.")
        case .secondToFirst: return tr("The other person speaks \(second). You read \(first).", "상대가 \(second)로 말합니다. \(first) 자막으로 봅니다.")
        case .firstCaptions: return tr("\(first) speech shown as \(first) captions. Nothing is translated.", "\(first) 말을 \(first) 자막으로 보여 줍니다. 번역은 하지 않습니다.")
        case .secondCaptions: return tr("\(second) speech shown as \(second) captions. Nothing is translated.", "\(second) 말을 \(second) 자막으로 보여 줍니다. 번역은 하지 않습니다.")
        case .conversation: return tr("You and the other person both speak. Each sentence is detected as \(first) or \(second) and translated into the other.", "나와 상대가 번갈아 말합니다. 문장마다 \(first)/\(second)를 자동으로 알아내 반대 언어로 번역합니다.")
        }
    }
}

/// Outcome of the first-run test: did this Mac hear, recognize and translate a played sentence?
enum SelfTestState: Equatable {
    case idle
    case running
    case passed(heard: String, translation: String?)
    case failed(String)
}

enum SessionStatus: Equatable {
    case idle
    case starting
    case listening
    case error(String)

    var isRunning: Bool { self == .starting || self == .listening }
}

struct TranscriptLine: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let text: String
    /// "en" or "ko": the language this sentence was spoken in.
    var language = ""
    /// Final translation of `text`, once the translator has delivered it.
    var translation: String?
    /// The last interim translation, shown (muted) until the final one arrives so the line never goes blank.
    var provisional: String?
    /// Which listening session produced this line; only the current session is back-filled with translations.
    var session = 0

    var displayTranslation: String? { translation ?? provisional }
}
