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

extension MeetingSetup {
    /// What the panel header and menus call the current setup: "English → Korean", "English ↔ Korean" or "Korean captions".
    @MainActor var title: String {
        guard let shown else { return tr("\(heard.name) captions", "\(heard.name) 자막") }
        return bothWays ? "\(heard.name) ↔ \(shown.name)" : "\(heard.name) → \(shown.name)"
    }

    /// One sentence that says what will happen, shown under the pickers.
    @MainActor var explanation: String {
        guard let shown else {
            return tr("\(heard.name) speech is shown as \(heard.name) captions. Nothing is translated.", "\(heard.name) 말을 \(heard.name) 자막으로 보여 줍니다. 번역은 하지 않습니다.")
        }
        if bothWays {
            return tr("You and the other person take turns. Each sentence is detected as \(heard.name) or \(shown.name) and translated into the other.",
                      "나와 상대가 번갈아 말합니다. 문장마다 \(heard.name)/\(shown.name)를 자동으로 알아내 반대 언어로 번역합니다.")
        }
        return tr("The other person speaks \(heard.name). You read \(shown.name).", "상대가 \(heard.name)로 말합니다. \(shown.name) 자막으로 봅니다.")
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
