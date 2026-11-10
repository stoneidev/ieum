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

/// Names and explanations for the meeting modes. The rules live in `MeetingMode` (CaptionCore).
extension MeetingMode {
    @MainActor var title: String {
        switch self {
        case .koreanToEnglish: tr("Korean → English", "한국어 → 영어")
        case .englishToKorean: tr("English → Korean", "영어 → 한국어")
        case .koreanCaptions: tr("Korean captions (no translation)", "한국어 자막 (번역 없음)")
        case .englishCaptions: tr("English captions (no translation)", "영어 자막 (번역 없음)")
        case .conversation: tr("Detect the language and translate", "언어 자동 인식 번역")
        }
    }

    /// The name for tight places such as the panel header; the full name says "(no translation)".
    @MainActor var shortTitle: String {
        switch self {
        case .koreanCaptions: tr("Korean captions", "한국어 자막")
        case .englishCaptions: tr("English captions", "영어 자막")
        default: title
        }
    }

    @MainActor var explanation: String {
        switch self {
        case .koreanToEnglish: tr("The other person speaks Korean. You read English.", "상대가 한국어로 말합니다. 영어 자막으로 봅니다.")
        case .englishToKorean: tr("The other person speaks English. You read Korean.", "상대가 영어로 말합니다. 한국어 자막으로 봅니다.")
        case .koreanCaptions: tr("Korean speech shown as Korean captions. Nothing is translated.", "한국어 말을 한국어 자막으로 보여 줍니다. 번역은 하지 않습니다.")
        case .englishCaptions: tr("English speech shown as English captions. Nothing is translated.", "영어 말을 영어 자막으로 보여 줍니다. 번역은 하지 않습니다.")
        case .conversation: tr("You and the other person both speak. Each sentence is detected as English or Korean and translated into the other.", "나와 상대가 번갈아 말합니다. 문장마다 영어/한국어를 자동으로 알아내 반대 언어로 번역합니다.")
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
