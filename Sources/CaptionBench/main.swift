import ArgumentParser
import Darwin
import Foundation
import CaptionCore

/// Runs a real audio file through the real engines in real time and reports latency, accuracy and cost.
@main
struct CaptionBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caption-bench",
        abstract: "Benchmarks recognition (and optionally translation) on a recorded audio file."
    )

    @Option(help: "Recognition locale, e.g. en-US, en-AU, ko-KR.")
    var locale = "en-US"
    @Option(help: "Audio file to play into the engine.")
    var file: String
    @Option(help: "Text file with the words that are spoken in the audio.")
    var referenceFile: String
    @Option(help: "Also translate into this language code (ko or en).")
    var translateTo: String?
    @Option(help: "Number of repetitions; the median is reported.")
    var runs = 3
    @Option(help: "Seconds of silence appended after the file.")
    var tail = 2.5
    @Option(help: "Free-form name for this case in the report.")
    var name: String?
    @Option(help: "Words to favor, comma separated (meeting vocabulary).")
    var vocabulary: String?
    @Flag(help: "Print every recognizer event with its time to stderr (diagnostics).")
    var dump = false
    @Option(help: "Write the JSON result here instead of stdout.")
    var output: String?
    @Flag(help: "Use the legacy SFSpeechRecognizer engine.")
    var legacy = false
    @Flag(help: "Conversation mode: recognize English and Korean in parallel and pick the spoken language per utterance.")
    var conversation = false
    @Option(help: "With --conversation: the languages spoken in the audio, in order, e.g. en,ko,en,ko.")
    var expectedLanguages: String?

    struct Run: Codable {
        var startupSeconds = 0.0
        var firstPartialSeconds: Double?
        var finalDelaySeconds: Double?
        var wer = 0.0
        var cer = 0.0
        var cpuPercent = 0.0
        var peakRSSMB = 0.0
        var finals = 0
        var recognized = ""
        var meanConfidence: Double?
        var languageSequence: String?
        var languageAccuracy: Double?
        var firstTranslationSeconds: Double?
        var finalTranslationLagSeconds: Double?
        var interimTranslationLagSeconds: Double?
        var translationNote: String?
    }

    struct Report: Codable {
        var name: String
        var locale: String
        var engine: String
        var audioSeconds: Double
        var speechSeconds: Double
        var runs: [Run]
        var median: Run
    }

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard let profile = FileAudioCapture.profile(of: url) else {
            throw ValidationError("Cannot read speech from \(file).")
        }
        let reference = (try String(contentsOfFile: referenceFile, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
        let options = EngineOptions(vocabulary: (vocabulary ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })

        var results: [Run] = []
        var engineName = ""
        for index in 0..<max(1, runs) {
            let (run, engine) = try await runOnce(url: url, profile: profile, reference: reference, options: options)
            engineName = engine
            results.append(run)
            FileHandle.standardError.write(Data("run \(index + 1)/\(runs): first \(fmt(run.firstPartialSeconds)) s, WER \(String(format: "%.0f%%", run.wer * 100))\n".utf8))
        }
        let report = Report(
            name: name ?? URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent,
            locale: locale, engine: engineName,
            audioSeconds: profile.duration, speechSeconds: profile.speechEnd - profile.speechStart,
            runs: results, median: Self.median(of: results)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    private func runOnce(url: URL, profile: FileAudioCapture.Profile, reference: String, options: EngineOptions) async throws -> (Run, String) {
        var run = Run()
        let capture = FileAudioCapture(url: url, tailSilence: tail)
        let clock = ContinuousClock()
        let usageBefore = Self.usage()
        let wallStart = clock.now

        let setupStart = clock.now
        let started = conversation
            ? try await EngineFactory.startConversation(locales: ["en-US", "ko-KR"], options: options, capture: capture)
            : try await EngineFactory.start(choice: legacy ? .legacy : .auto, localeID: locale, options: options, capture: capture)
        guard let zero = capture.startedAt else { throw ValidationError("capture did not start") }
        run.startupSeconds = Self.seconds(zero - setupStart)

        // Translation runs exactly like the app: interim text is submitted as it arrives, finals in order.
        var pipeline: TranslationPipeline?
        var collector: Task<TranslationStats, Never>?
        var pendingFinalTimes: [UUID: ContinuousClock.Instant] = [:]
        var finalIDs: [UUID] = []
        var interimSubmitTimes: [String: ContinuousClock.Instant] = [:]
        if let target = translateTo {
            let source = locale.hasPrefix("ko") ? "ko" : "en"
            let finals = await SystemTranslation.makeTranslator(from: source, to: target)
            let interims = await SystemTranslation.makeTranslator(from: source, to: target)
            switch (finals, interims) {
            case (.success(let finalTranslator), .success(let interimTranslator)):
                let p = TranslationPipeline(translator: finalTranslator, interimTranslator: interimTranslator)
                pipeline = p
                collector = Task { await Self.collect(p, clock: clock) }
            case (.failure(let reason), _), (_, .failure(let reason)):
                run.translationNotice(reason.message)
            }
        }

        var finalsText: [String] = []
        var confidences: [Double] = []
        var languages: [String] = []
        var lastFinal: ContinuousClock.Instant?
        for try await event in started.events {
            let now = clock.now
            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if dump {
                let range = event.audioStart.map { String(format: "%.1f-%.1f", $0, event.audioEnd ?? 0) } ?? "-"
                FileHandle.standardError.write(Data(String(format: "%6.2fs %@ %@ conf=%@ range=%@ | %@\n", Self.seconds(now - zero), event.locale, event.isFinal ? "FINAL " : "interim", event.confidence.map { String(format: "%.2f", $0) } ?? "-", range, text).utf8))
            }
            if event.isFinal {
                guard !text.isEmpty else { continue }
                finalsText.append(text)
                if let c = event.confidence { confidences.append(c) }
                let language = String(event.locale.prefix(2))
                if languages.last != language { languages.append(language) }
                lastFinal = now
                run.finals += 1
                if let pipeline {
                    let id = UUID()
                    pendingFinalTimes[id] = now
                    finalIDs.append(id)
                    await pipeline.submitFinal(id: id, text: text)
                }
            } else if !text.isEmpty {
                if run.firstPartialSeconds == nil { run.firstPartialSeconds = Self.seconds(now - zero) - profile.speechStart }
                if let pipeline {
                    if interimSubmitTimes[text] == nil { interimSubmitTimes[text] = now }
                    await pipeline.submitInterim(text)
                }
            }
        }
        if let lastFinal { run.finalDelaySeconds = Self.seconds(lastFinal - zero) - profile.speechEnd }
        run.recognized = finalsText.joined(separator: " ")
        if conversation {
            run.languageSequence = languages.joined(separator: ",")
            if let expected = expectedLanguages?.split(separator: ",").map(String.init) {
                run.languageAccuracy = TextMetrics.sequenceSimilarity(languages, expected)
            }
        }
        run.meanConfidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        run.wer = TextMetrics.wordErrorRate(reference: reference, hypothesis: run.recognized)
        run.cer = TextMetrics.characterErrorRate(reference: reference, hypothesis: run.recognized)

        if let pipeline, let collector {
            // Give the last sentences time to be translated, then close and read what arrived.
            try? await Task.sleep(for: .seconds(4))
            await pipeline.close()
            let stats = await collector.value
            run.firstTranslationSeconds = stats.firstInterim.map { Self.seconds($0 - zero) - profile.speechStart }
            let finalLags = finalIDs.compactMap { id -> Double? in
                guard let out = stats.finals[id], let at = pendingFinalTimes[id] else { return nil }
                return Self.seconds(out - at)
            }
            run.finalTranslationLagSeconds = finalLags.isEmpty ? nil : finalLags.reduce(0, +) / Double(finalLags.count)
            let interimLags = stats.interims.compactMap { (source, out) -> Double? in
                interimSubmitTimes[source].map { Self.seconds(out - $0) }
            }
            run.interimTranslationLagSeconds = interimLags.isEmpty ? nil : interimLags.reduce(0, +) / Double(interimLags.count)
        }

        let usageAfter = Self.usage()
        let wall = Self.seconds(clock.now - wallStart)
        run.cpuPercent = wall > 0 ? (usageAfter.cpu - usageBefore.cpu) / wall * 100 : 0
        run.peakRSSMB = usageAfter.peakRSSMB
        return (run, started.engine.name)
    }

    // MARK: Translation bookkeeping

    struct TranslationStats {
        var firstInterim: ContinuousClock.Instant?
        var interims: [(String, ContinuousClock.Instant)] = []
        var finals: [UUID: ContinuousClock.Instant] = [:]
    }

    static func collect(_ pipeline: TranslationPipeline, clock: ContinuousClock) async -> TranslationStats {
        var stats = TranslationStats()
        for await output in pipeline.outputs {
            let now = clock.now
            switch output {
            case .interim(let source, _):
                if stats.firstInterim == nil { stats.firstInterim = now }
                stats.interims.append((source, now))
            case .final(let id, _): stats.finals[id] = now
            case .failed: break
            }
        }
        return stats
    }

    // MARK: Helpers

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    static func usage() -> (cpu: Double, peakRSSMB: Double) {
        var info = rusage()
        getrusage(RUSAGE_SELF, &info)
        func sec(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        // ru_maxrss is in bytes on macOS.
        return (sec(info.ru_utime) + sec(info.ru_stime), Double(info.ru_maxrss) / 1_048_576)
    }

    static func median(of runs: [Run]) -> Run {
        func med(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        var result = runs[runs.count / 2]
        result.startupSeconds = med(runs.map(\.startupSeconds)) ?? 0
        result.firstPartialSeconds = med(runs.compactMap(\.firstPartialSeconds))
        result.finalDelaySeconds = med(runs.compactMap(\.finalDelaySeconds))
        result.wer = med(runs.map(\.wer)) ?? 0
        result.cer = med(runs.map(\.cer)) ?? 0
        result.languageAccuracy = med(runs.compactMap(\.languageAccuracy))
        result.cpuPercent = med(runs.map(\.cpuPercent)) ?? 0
        result.peakRSSMB = runs.map(\.peakRSSMB).max() ?? 0
        result.firstTranslationSeconds = med(runs.compactMap(\.firstTranslationSeconds))
        result.finalTranslationLagSeconds = med(runs.compactMap(\.finalTranslationLagSeconds))
        result.interimTranslationLagSeconds = med(runs.compactMap(\.interimTranslationLagSeconds))
        return result
    }

    private func fmt(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "n/a" }
}

extension CaptionBench.Run {
    mutating func translationNotice(_ message: String) { translationNote = message }
}
