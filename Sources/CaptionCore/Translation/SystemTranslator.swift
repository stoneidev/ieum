#if compiler(>=6.2)
import Foundation
import Translation

/// Apple's on-device Translation framework. Nothing is sent over the network once the language pair is installed.
///
/// Installation is tracked per strategy: the low-latency model is optional and often absent while the standard
/// (high-fidelity) one is present. So the strategy is chosen up front from what is actually installed.
@available(macOS 26.4, *)
final class SystemTranslator: TextTranslator, @unchecked Sendable {
    // `TranslationSession` is not Sendable. `TranslationPipeline` calls this one request at a time.
    private let session: TranslationSession

    private init(source: Locale.Language, target: Locale.Language, lowLatency: Bool) {
        session = TranslationSession(
            installedSource: source, target: target,
            preferredStrategy: lowLatency ? .lowLatency : .highFidelity
        )
    }

    static func make(from sourceCode: String, to targetCode: String) async -> Result<any TextTranslator, TranslationUnavailable> {
        let source = Locale.Language(identifier: SpokenLanguage(code: sourceCode)?.translationIdentifier ?? sourceCode)
        let target = Locale.Language(identifier: SpokenLanguage(code: targetCode)?.translationIdentifier ?? targetCode)
        let low = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: source, to: target)
        if low == .installed {
            return .success(SystemTranslator(source: source, target: target, lowLatency: true))
        }
        switch await LanguageAvailability(preferredStrategy: .highFidelity).status(from: source, to: target) {
        case .installed:
            return .success(SystemTranslator(source: source, target: target, lowLatency: false))
        case .supported:
            return .failure(TranslationUnavailable(
                "The \(sourceCode) → \(targetCode) translation language is not downloaded. Add it in System Settings > General > Language & Region > Translation Languages."
            ))
        case .unsupported:
            return .failure(TranslationUnavailable("Translating \(sourceCode) → \(targetCode) is not supported on this Mac."))
        @unknown default:
            return .failure(TranslationUnavailable("Translation is not available for \(sourceCode) → \(targetCode)."))
        }
    }

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}
#endif
