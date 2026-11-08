import Foundation

public enum EngineChoice: String, CaseIterable, Sendable {
    case auto
    case modern
    case legacy
}

/// Picks and starts an engine: modern first, legacy when the modern one cannot serve the request.
public enum EngineFactory {
    public static func start(
        choice: EngineChoice,
        localeID: String,
        options: EngineOptions,
        capture: any AudioCapture
    ) async throws -> (engine: any TranscriberEngine, events: AsyncThrowingStream<TranscriptionEvent, Error>) {
        let started = try await startEngine(choice: choice, localeID: localeID, options: options, capture: capture)
        // The user's vocabulary also repairs the transcript afterwards: engines use it unevenly (see VocabularyCorrector).
        return (started.engine, options.correctsTranscript ? VocabularyCorrector(terms: options.vocabulary).apply(to: started.events) : started.events)
    }

    private static func startEngine(
        choice: EngineChoice,
        localeID: String,
        options: EngineOptions,
        capture: any AudioCapture
    ) async throws -> (engine: any TranscriberEngine, events: AsyncThrowingStream<TranscriptionEvent, Error>) {
        if choice != .legacy {
            do {
                if let modern = try await ModernSpeechSupport.makeEngine(localeID: localeID, options: options) {
                    if options.showsWordsSooner, let early = await PreviewingEngine.makePreviewEngine(localeID: localeID, options: options) {
                        let both = PreviewingEngine(primary: modern, preview: early)
                        return (both, try await both.events(from: capture))
                    }
                    return (modern, try await modern.events(from: capture))
                }
                if choice == .modern {
                    throw EngineError.engineUnavailable("SpeechAnalyzer requires macOS 26 or later.")
                }
            } catch let error as EngineError where choice == .auto && error.allowsFallback {
                log("modern engine unavailable (\(error.localizedDescription)); using SFSpeechRecognizer")
            }
        }
        let legacy = try OnDeviceSpeechEngine(localeID: localeID, options: options)
        return (legacy, try await legacy.events(from: capture))
    }

    /// Two-way conversation: recognizes every language in parallel and keeps, per utterance, the one that was spoken.
    public static func startConversation(
        locales: [String],
        options: EngineOptions,
        capture: any AudioCapture
    ) async throws -> (engine: any TranscriberEngine, events: AsyncThrowingStream<TranscriptionEvent, Error>) {
        let engine = ConversationEngine(locales: locales, options: options)
        let events = try await engine.events(from: capture)
        return (engine, options.correctsTranscript ? VocabularyCorrector(terms: options.vocabulary).apply(to: events) : events)
    }

    /// Supported on-device locales as BCP-47 identifiers.
    public static func supportedLocaleIdentifiers() async -> [String] {
        // Probing SFSpeechRecognizer per locale makes the system log noise to stderr, so only do it
        // when the modern engine (which has a direct locale list) is unavailable.
        var identifiers = await ModernSpeechSupport.supportedLocaleIdentifiers()
        if identifiers.isEmpty { identifiers = OnDeviceSpeechEngine.supportedLocaleIdentifiers() }
        return Set(identifiers).sorted()
    }
}
