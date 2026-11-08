import ArgumentParser
import Foundation
import MacSTTCore

enum SourceKind: String, CaseIterable {
    case mic
    case system
}

extension OutputFormat: ExpressibleByArgument {}
extension SourceKind: ExpressibleByArgument {}
extension EngineChoice: ExpressibleByArgument {}

@main
struct MacSTTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mac-stt",
        abstract: "Real-time, fully on-device speech-to-text for macOS.",
        discussion: """
        Uses SpeechAnalyzer/SpeechTranscriber on macOS 26+ and falls back to on-device \
        SFSpeechRecognizer elsewhere. Press Ctrl+C to stop; pending text is flushed first.
        """
    )

    @Option(name: .long, help: "Locale to transcribe, e.g. ko-KR, en-US, en-AU, ja-JP.")
    var locale: String = "ko-KR"

    @Option(name: .long, help: "Audio source: mic or system (desktop audio via ScreenCaptureKit).")
    var source: SourceKind = .mic

    @Option(name: .long, help: "Output format: text (live line + timestamped finals) or jsonl.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Speech engine: auto, modern (SpeechAnalyzer), or legacy (SFSpeechRecognizer).")
    var engine: EngineChoice = .auto

    @Flag(name: .long, inversion: .prefixedNo, help: "Report partial results sooner at some cost in accuracy (modern engine).")
    var fast = true

    @Flag(name: .long, inversion: .prefixedNo, help: "Voice activity detection in the modern engine. Turning it off can help accuracy.")
    var vad = true

    @Flag(name: .long, help: "Mic only: apply system voice processing (noise suppression, AGC, echo cancellation).")
    var voiceProcessing = false

    @Flag(name: .long, help: "Experimental: lightly correct finalized sentences with Apple's on-device language model (adds ~0.5s per sentence; edits that change meaning are rejected).")
    var polish = false

    @Option(name: .customLong("word"), help: "A word or phrase to favor, e.g. a name or jargon term. Repeatable.")
    var words: [String] = []

    @Option(name: .long, help: "File with one word or phrase per line to favor (# starts a comment).", completion: .file())
    var wordsFile: String?

    @Flag(name: .long, help: "Print all supported on-device locales and exit.")
    var listLocales = false

    func run() async throws {
        if listLocales {
            await Self.printLocales()
            return
        }

        if voiceProcessing && source != .mic {
            throw ValidationError("--voice-processing only applies to --source mic.")
        }
        var vocabulary = words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let wordsFile {
            guard let text = try? String(contentsOfFile: wordsFile, encoding: .utf8) else {
                throw ValidationError("Cannot read --words-file '\(wordsFile)'.")
            }
            vocabulary += EngineOptions.parseVocabulary(text)
        }
        let options = EngineOptions(fast: fast, useVAD: vad, vocabulary: vocabulary)

        let polisher = polish ? await FinalTextPolisher.onDevice() : nil
        let capture: any AudioCapture = source == .mic ? MicrophoneCapture(voiceProcessing: voiceProcessing) : SystemAudioCapture()
        let (engine, events) = try await EngineFactory.start(choice: engine, localeID: locale, options: options, capture: capture)
        log("engine: \(engine.name), locale: \(locale), source: \(source.rawValue) (Ctrl+C to stop)")

        let interactive = isatty(STDOUT_FILENO) == 1
        let pipeline = OutputPipeline(
            formatter: OutputFormatter(format: format, interactive: interactive),
            currentColumns: { interactive ? terminalColumns() : nil }
        )
        let stopping = StopFlag()
        let traps = SignalTrap(signals: [SIGINT, SIGTERM]) { count in
            if count == 1 {
                stopping.set()
                Task {
                    await engine.stop()
                    // Safety net: if the engine does not drain in time, flush and leave.
                    try? await Task.sleep(for: .seconds(6))
                    pipeline.finish()
                    Darwin.exit(0)
                }
            } else {
                pipeline.finish()
                Darwin.exit(130)
            }
        }
        defer { traps.cancel() }

        do {
            for try await event in events {
                pipeline.handle(await polisher?.apply(to: event) ?? event)
            }
        } catch {
            pipeline.finish()
            // A recognizer error while winding down (e.g. it rejects a stream of pure silence) is not a failure.
            if stopping.isSet {
                log("stopped; recognizer reported: \(error.localizedDescription)")
                return
            }
            throw error
        }
        pipeline.finish()
    }

    private static func printLocales() async {
        StdoutWriter.write(await EngineFactory.supportedLocaleIdentifiers().joined(separator: "\n") + "\n")
    }
}

func terminalColumns() -> Int? {
    var size = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return nil }
    return Int(size.ws_col)
}

final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Traps signals with `DispatchSource` so shutdown runs as normal code, not inside a signal handler.
final class SignalTrap: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mac-stt.signals")
    private var sources: [any DispatchSourceSignal] = []
    private var count = 0

    /// `handler` receives how many signals have arrived so far (1 = graceful stop, 2+ = force quit).
    init(signals: [Int32], handler: @escaping @Sendable (Int) -> Void) {
        for number in signals {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.count += 1
                handler(self.count)
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
}
