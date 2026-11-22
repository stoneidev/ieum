import CaptionCore
import FoundationModels
import Foundation

/// Writes a draft of meeting minutes with the on-device language model (Apple Intelligence). Nothing leaves the Mac.
enum MinutesGenerator {
    enum Status {
        case ready
        /// This Mac cannot offer minutes at all (macOS before 26, or no Apple Intelligence): the feature is not shown.
        case notOffered
        /// This Mac can, but not right now: shown greyed out with the reason.
        case unavailable(String)
    }

    @MainActor
    static func status(for language: SpokenLanguage) -> Status {
        guard #available(macOS 26.0, *) else { return .notOffered }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return .notOffered
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(tr("Turn on Apple Intelligence in System Settings.", "시스템 설정에서 Apple Intelligence를 켜세요."))
        case .unavailable(.modelNotReady):
            return .unavailable(tr("The language model is still downloading. Try again later.", "언어 모델을 내려받는 중입니다. 잠시 뒤에 다시 시도하세요."))
        case .unavailable:
            return .unavailable(tr("The language model is not available.", "언어 모델을 사용할 수 없습니다."))
        }
        guard model.supportsLocale(Locale(identifier: language.code)) else {
            return .unavailable(tr("Apple Intelligence does not support this language yet.", "Apple Intelligence가 아직 이 언어를 지원하지 않습니다."))
        }
        return .ready
    }

    /// Whether this Mac can ever make minutes (used to show the feature and its "What's new" page only to people who can use it).
    @MainActor
    static var isOffered: Bool {
        if case .notOffered = status(for: .english) { false } else { true }
    }
}
