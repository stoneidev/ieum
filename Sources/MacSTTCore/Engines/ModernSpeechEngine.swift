import AVFoundation
import Foundation

/// Entry points that compile on every SDK; the real engine only exists with the macOS 26 Speech SDK.
enum ModernSpeechSupport {
    static func makeEngine(localeID: String, options: EngineOptions) async throws -> (any TranscriberEngine)? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return try await ModernSpeechEngine(localeID: localeID, options: options)
        }
        #endif
        return nil
    }

    /// Locales the SpeechTranscriber model family supports (some may still need a one-time asset download).
    static func supportedLocaleIdentifiers() async -> [String] {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return await ModernSpeechEngine.supportedLocaleIdentifiers()
        }
        #endif
        return []
    }
}

#if compiler(>=6.2)
import CoreMedia
import Speech

/// Primary engine: SpeechAnalyzer + SpeechTranscriber (+ SpeechDetector VAD), running on the ANE.
@available(macOS 26.0, *)
actor ModernSpeechEngine: TranscriberEngine {
    nonisolated var name: String { "SpeechAnalyzer / SpeechTranscriber" }

    private let localeID: String
    private let locale: Locale
    private let options: EngineOptions
    private var capture: (any AudioCapture)?

    init(localeID: String, options: EngineOptions) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw EngineError.engineUnavailable("SpeechTranscriber is not available on this device.")
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw EngineError.unsupportedLocale("Locale '\(localeID)' is not supported by SpeechTranscriber.")
        }
        self.localeID = localeID
        self.locale = resolved
        self.options = options
    }

    static func supportedLocaleIdentifiers() async -> [String] {
        await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    }

    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: options.fast ? [.volatileResults, .fastResults] : [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        var modules: [any SpeechModule] = [transcriber]
        if options.useVAD {
            modules.append(SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false))
        }

        try await ensureAssets(for: modules)
        _ = try? await AssetInventory.reserve(locale: locale)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw EngineError.engineUnavailable("No compatible audio format for SpeechAnalyzer.")
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        if !options.vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = options.vocabulary
            try await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (input, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .unbounded)
        try await analyzer.start(inputSequence: input)

        let audio = try await capture.start()
        self.capture = capture

        let localeID = self.localeID
        return AsyncThrowingStream { continuation in
            let results = Task {
                do {
                    for try await result in transcriber.results {
                        let range = result.range
                        let hasRange = range.isValid && !range.isEmpty
                        continuation.yield(TranscriptionEvent(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            locale: localeID,
                            audioStart: hasRange ? range.start.seconds : nil,
                            audioEnd: hasRange ? range.end.seconds : nil
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let feed = Task {
                var converter: PCMConverter?
                for await chunk in audio {
                    if Task.isCancelled { break }
                    if converter == nil {
                        converter = PCMConverter(from: chunk.buffer.format, to: analyzerFormat)
                    }
                    guard let converted = converter?.convert(chunk.buffer) else { continue }
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
                inputContinuation.finish()
                // Flushes volatile text into final results; `results` ends afterwards.
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            continuation.onTermination = { _ in
                feed.cancel()
                results.cancel()
                Task {
                    await capture.stop()
                    await analyzer.cancelAndFinishNow()
                }
            }
        }
    }

    func stop() async {
        await capture?.stop()
    }

    /// Reports clearly when the locale's on-device model must be downloaded, then installs it.
    private func ensureAssets(for modules: [any SpeechModule]) async throws {
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            return
        case .unsupported:
            throw EngineError.unsupportedLocale("Locale '\(localeID)' is not supported by SpeechTranscriber on this Mac.")
        case .supported, .downloading:
            log("Speech assets for '\(localeID)' are not installed yet; downloading (one-time, system-managed)...")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            log("Speech assets for '\(localeID)' installed.")
        @unknown default:
            return
        }
    }
}
#endif
