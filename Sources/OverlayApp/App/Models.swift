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
    /// A call: the microphone is the person at this Mac and the system audio is the other side, each recognized in its own language.
    case call

    @MainActor var title: String {
        switch self {
        case .microphone: tr("Microphone", "마이크")
        case .system: tr("System audio", "시스템 소리")
        case .call: tr("Call (microphone + system audio)", "통화 (마이크 + 시스템 소리)")
        }
    }

    /// Recognizing two sides at once uses two recognizers of the newer kind.
    var isAvailableOnThisMac: Bool { self != .call || MeetingSetup.bothWaysIsAvailableOnThisMac }
}

extension InputAdvice {
    /// What is wrong and what to try, for the source in use.
    @MainActor func message(for source: Source) -> String? {
        switch (self, source) {
        case (.good, _):
            return nil
        case (.silent, .system):
            return tr("No sound is playing on this Mac. Start the video or the call, or check that its sound is not muted.",
                      "이 Mac에서 재생되는 소리가 없어요. 영상이나 회의를 재생하고 소리가 꺼져 있지 않은지 확인하세요.")
        case (.silent, _):
            return tr("The microphone hears nothing. Check that it is not muted and that the right one is chosen.",
                      "마이크에 아무 소리도 들어오지 않아요. 음소거가 아닌지, 올바른 마이크가 선택됐는지 확인하세요.")
        case (.tooQuiet, .system):
            return tr("The sound is very quiet. Turn up the volume of what is playing.", "소리가 매우 작아요. 재생 중인 소리의 볼륨을 높여 보세요.")
        case (.tooQuiet, _):
            return tr("Speech is too quiet to read well. Move the microphone closer to the speaker.", "말소리가 너무 작아요. 마이크를 말하는 사람 가까이 두세요.")
        case (.tooLoud, _):
            return tr("The sound is so loud it distorts. Lower the volume or move the microphone away.", "소리가 너무 커서 깨져요. 볼륨을 낮추거나 마이크를 멀리 두세요.")
        }
    }

    /// Whether choosing another microphone could fix it.
    var suggestsAnotherMicrophone: Bool { self == .silent || self == .tooQuiet }
}

extension Source {
    /// The name on a choice or a pill: short, because the situation and the languages sit beside it.
    @MainActor var shortTitle: String {
        switch self {
        case .microphone: tr("Microphone", "마이크")
        case .system: tr("System audio", "시스템 소리")
        case .call: tr("Call", "통화")
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic"
        case .system: "speaker.wave.2"
        case .call: "phone"
        }
    }

    /// Where the sound comes from, in plain words.
    @MainActor var hint: String {
        switch self {
        case .microphone: tr("Captions what the microphone hears: the room, a talk, you.", "마이크로 들리는 소리: 같은 공간의 대화, 강연, 내 목소리")
        case .system: tr("Captions what plays on this Mac: a video call, a recording. Needs the Screen & System Audio Recording permission.",
                         "이 Mac에서 재생되는 소리: 화상회의, 영상. 화면 및 시스템 오디오 녹음 권한이 필요합니다.")
        case .call: tr("Both sides of a video call: the other side from the system audio, you from the microphone, each line labelled Me or Them.",
                       "화상 통화의 양쪽: 상대는 시스템 소리, 나는 마이크로 받고 줄마다 나/상대를 표시합니다.")
        }
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

extension TranslationUnavailable {
    /// The same message in the interface language, naming the languages the way the rest of the app does.
    @MainActor var localizedMessage: String {
        func name(_ code: String) -> String { SpokenLanguage(code: code)?.name ?? code }
        switch kind {
        case .notDownloaded(let source, let target):
            return tr("Translation from \(name(source)) to \(name(target)) is not downloaded yet. Open the ⋯ menu > Permissions and setup… and press Download language.",
                      "\(name(source)) → \(name(target)) 번역 언어를 아직 내려받지 않았습니다. ⋯ 메뉴 > 권한 및 설정 점검…에서 '언어 내려받기'를 누르세요.")
        case .unsupported(let source, let target):
            return tr("Translating \(name(source)) to \(name(target)) is not supported on this Mac.", "이 Mac에서는 \(name(source)) → \(name(target)) 번역을 지원하지 않습니다.")
        case .needsNewerMacOS:
            return tr("Offline translation needs macOS 26.4 or later.", "오프라인 번역은 macOS 26.4 이상이 필요합니다.")
        case .other:
            return message
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
    /// In a call, who said it.
    var speaker: Speaker?
    /// Final translation of `text`, once the translator has delivered it.
    var translation: String?
    /// The last interim translation, shown (muted) until the final one arrives so the line never goes blank.
    var provisional: String?
    /// Which listening session produced this line; only the current session is back-filled with translations.
    var session = 0

    var displayTranslation: String? { translation ?? provisional }
}

/// The two pages of the transcript panel: the conversation, and the minutes opened from the end of a meeting.
enum PanelPage: Equatable {
    case conversation, minutes
}

/// Where the minutes draft of the last meeting stands.
enum MinutesState: Equatable {
    case idle
    case working(done: Int, total: Int)
    case ready
    case failed(String)
}

extension Scenario {
    @MainActor var title: String {
        switch self {
        case .conversation: tr("Conversation", "대화")
        case .meeting: tr("Meeting", "회의")
        case .seminar: tr("Seminar or talk", "세미나·강연")
        }
    }

    @MainActor var explanation: String {
        switch self {
        case .conversation: tr("Two people talking in the same room. Both speak, so each sentence is translated into the other language.",
                               "같은 공간에서 두 사람이 이야기합니다. 서로 번갈아 말하므로 문장마다 상대 언어로 번역합니다.")
        case .meeting: tr("Several people, often on a video call. Reads the other side from this Mac's sound, or the room from the microphone. Notes list decisions and tasks.",
                          "여러 사람이 참여하고 주로 화상회의입니다. 이 Mac의 소리나 마이크로 듣습니다. 정리에는 결정 사항과 할 일이 들어갑니다.")
        case .seminar: tr("A talk or lecture you only listen to, in one language. No both-sides mode. Notes list the key points and the questions raised.",
                          "한 언어로 진행되는 강연을 듣기만 합니다. 서로 번갈아 말하는 모드는 없습니다. 정리에는 핵심 내용과 나온 질문이 들어갑니다.")
        }
    }

    /// The name of the minutes page and of the notes themselves.
    @MainActor var notesTitle: String {
        switch self {
        case .conversation: tr("Summary", "대화 요약")
        case .meeting: tr("Minutes", "회의록")
        case .seminar: tr("Lecture notes", "강의 노트")
        }
    }

    @MainActor var endedPrompt: String {
        switch self {
        case .conversation: tr("The conversation ended. Write the summary", "대화가 끝났습니다. 요약 만들기")
        case .meeting: tr("The meeting ended. Write the minutes", "회의가 끝났습니다. 회의록 초안 만들기")
        case .seminar: tr("The talk ended. Write the lecture notes", "강연이 끝났습니다. 강의 노트 만들기")
        }
    }

    var allowedSources: [Source] {
        Source.allCases.filter { source in
            switch source {
            case .microphone: true
            case .system: allowsSystemAudio
            case .call: allowsCall
            }
        }
    }

    var defaultSource: Source { prefersSystemAudio ? .system : .microphone }
}

extension Scenario {
    /// What the person calls the event ("the meeting is still going").
    @MainActor var stillGoing: String {
        switch self {
        case .conversation: tr("The conversation is still going", "대화 중입니다")
        case .meeting: tr("The meeting is still going", "회의 중입니다")
        case .seminar: tr("The talk is still going", "강연 중입니다")
        }
    }

    @MainActor var nothingYet: String {
        switch self {
        case .conversation: tr("No conversation to summarize yet", "아직 정리할 대화가 없습니다")
        case .meeting: tr("No meeting to summarize yet", "아직 정리할 회의가 없습니다")
        case .seminar: tr("No talk to summarize yet", "아직 정리할 강연이 없습니다")
        }
    }

    /// What the notes contain, in a sentence.
    @MainActor var contents: String {
        switch self {
        case .conversation: tr("a summary, the points worth remembering and what to follow up", "요약, 기억할 내용, 챙겨야 할 일")
        case .meeting: tr("a summary, the decisions, the action items and what was left open", "요약, 결정 사항, 할 일, 남은 질문")
        case .seminar: tr("a summary, the key points and the questions raised", "요약, 핵심 내용, 나온 질문")
        }
    }
}

extension Scenario {
    /// One short line for a menu or a choice tile.
    @MainActor var hint: String {
        switch self {
        case .conversation: tr("Two people in the same room", "같은 공간의 두 사람")
        case .meeting: tr("Several people, often on a video call", "여러 사람, 주로 화상회의")
        case .seminar: tr("A talk you only listen to", "듣기만 하는 강연")
        }
    }

    var symbol: String {
        switch self {
        case .conversation: "bubble.left.and.bubble.right"
        case .meeting: "person.3"
        case .seminar: "graduationcap"
        }
    }
}

extension Scenario {
    /// The name on the small pill: shorter than the full title so the languages next to it keep their room.
    @MainActor var chipTitle: String {
        switch self {
        case .conversation: tr("Conversation", "대화")
        case .meeting: tr("Meeting", "회의")
        case .seminar: tr("Seminar", "세미나")
        }
    }
}

extension PointerAvoidance {
    @MainActor var title: String {
        switch self {
        case .fade: tr("Turn see-through and let clicks pass", "반투명해지고 클릭을 통과시킴")
        case .dodge: tr("Move to the opposite edge of the screen", "화면 반대편 가장자리로 비켜남")
        case .off: tr("Do nothing", "아무것도 하지 않음")
        }
    }
}
