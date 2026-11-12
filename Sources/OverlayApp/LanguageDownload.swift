import SwiftUI
@preconcurrency import Translation
import CaptionCore

/// A translation language the person asked to download. The system shows its own download sheet for it.
struct LanguageDownloadRequest: Equatable {
    let source: String
    let target: String
    private let id = UUID()

    init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

extension View {
    /// Lets this window ask macOS to download a translation language (Translation framework, macOS 15 and later):
    /// set `request`, the system presents its download sheet, and `finished` runs when it is closed.
    @ViewBuilder
    func languageDownload(_ request: Binding<LanguageDownloadRequest?>, finished: @escaping () -> Void) -> some View {
        if #available(macOS 15.0, *) {
            modifier(LanguageDownloadModifier(request: request, finished: finished))
        } else {
            self
        }
    }
}

@available(macOS 15.0, *)
private struct LanguageDownloadModifier: ViewModifier {
    @Binding var request: LanguageDownloadRequest?
    let finished: () -> Void
    @State private var configuration: TranslationSession.Configuration?

    private func language(_ code: String) -> Locale.Language {
        Locale.Language(identifier: SpokenLanguage(code: code)?.translationIdentifier ?? code)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                configuration = TranslationSession.Configuration(source: language(new.source), target: language(new.target))
            }
            .translationTask(configuration) { session in
                // Shows the system's "download languages" sheet when something is missing; returns at once when it is not.
                do { try await session.prepareTranslation() } catch { log("Translation language download: \(error.localizedDescription)") }
                request = nil
                configuration = nil
                finished()
            }
    }
}
