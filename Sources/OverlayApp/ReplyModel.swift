import AppKit
import CaptionCore
import FoundationModels
import Foundation

/// The language model that smooths a plain translation into something a person would say. Optional: without Apple
/// Intelligence the plain translation is what the reply is.
enum ReplyPolisher {
    @MainActor
    static func isAvailable(for target: SpokenLanguage) -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Locale(identifier: target.code))
    }

    static func polish(draft: String, original: String, from: SpokenLanguage, target: SpokenLanguage) async -> String? {
        guard #available(macOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: ReplyPrompt.instructions(for: target))
        guard let response = try? await session.respond(to: "Original (\(from.name)): \(original)\nDraft: \(draft)", options: GenerationOptions(temperature: 0)) else { return nil }
        let text = response.content.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'「」 \n"))
        return ReplyHelper.acceptsPolished(literal: draft, candidate: text, target: target) ? text : nil
    }
}

/// The reply helper: what was typed or said in one language, the sentence to read out in the other.
@MainActor
final class ReplyModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case translating
        case ready
        case failed(String)
    }

    @Published var input = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var literal = ""
    @Published private(set) var polished: String?
    @Published private(set) var polishing = false
    @Published private(set) var history = ReplyHistory()
    @Published private(set) var listening = false
    @Published private(set) var copied = false
    /// Translate from the language of the other side into the one you read, to check what a sentence means.
    @Published private(set) var reversed = false
    /// Bumped each time the panel opens, so the text field takes the keyboard again.
    @Published private(set) var focusToken = 0

    let app: AppModel
    private var translators: [String: any TextTranslator] = [:]
    private var run = 0
    private var dictation: Task<Void, Never>?
    private var dictationEngine: (any TranscriberEngine)?

    init(app: AppModel) { self.app = app }

    /// What the person says, and what the other side hears: nil when there is no language to read (no translation chosen).
    var pair: (from: SpokenLanguage, to: SpokenLanguage)? {
        guard let shown = app.setup.shown else { return nil }
        return reversed ? (app.setup.heard, shown) : (shown, app.setup.heard)
    }

    /// The sentence to read out: the smoothed one when there is one, else the plain translation.
    var reply: String { polished ?? literal }

    func opened() {
        focusToken += 1
        copied = false
    }

    func toggleDirection() {
        cancelListening()
        reversed.toggle()
        reset()
    }

    func reset() {
        run += 1
        phase = .idle
        literal = ""
        polished = nil
        polishing = false
    }

    func submit() {
        guard let pair, let text = ReplyHelper.prepare(input) else { return }
        run += 1
        let mine = run
        phase = .translating
        polished = nil
        polishing = false
        Task { [weak self] in
            guard let self else { return }
            let key = "\(pair.from.code)>\(pair.to.code)"
            do {
                let translator: any TextTranslator
                if let cached = translators[key] {
                    translator = cached
                } else {
                    switch await SystemTranslation.makeTranslator(from: pair.from.code, to: pair.to.code) {
                    case .success(let made): translator = made; translators[key] = made
                    case .failure(let failure):
                        if mine == run { phase = .failed(failure.localizedMessage) }
                        return
                    }
                }
                let translated = try await translator.translate(text)
                guard mine == run else { return }
                literal = translated
                phase = .ready
                history.add(source: text, reply: translated)
                await smooth(text: translated, target: pair.to, from: pair.from, run: mine, source: text)
            } catch {
                if mine == run { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func smooth(text: String, target: SpokenLanguage, from: SpokenLanguage, run mine: Int, source: String) async {
        guard app.smoothsReplies, ReplyPolisher.isAvailable(for: target) else { return }
        polishing = true
        let better = await ReplyPolisher.polish(draft: text, original: source, from: from, target: target)
        guard mine == run else { return }
        polishing = false
        if let better, better != text {
            polished = better
            history.add(source: source, reply: better)
        }
    }

    func copy(_ text: String? = nil) {
        let value = text ?? reply
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.copied = false
        }
    }

    func clear() {
        cancelListening()
        input = ""
        reset()
    }

    // MARK: Speaking instead of typing

    /// Listens for one sentence in the language you read, then translates it. Only the microphone and the speech
    /// recognizer the captions already use; nothing is recorded.
    func toggleListening() {
        if listening {
            stopListening()
            return
        }
        guard let pair else { return }
        listening = true
        app.dictationActive = true
        let locale = app.recognitionLocale(for: pair.from)
        let device = app.inputDeviceUID
        dictation = Task { [weak self] in
            var heard: String?
            do {
                let capture = MicrophoneCapture(voiceProcessing: false, deviceUID: InputDevices.resolve(preferredUID: device, available: InputDevices.available()))
                var options = EngineOptions()
                options.correctsTranscript = false
                let started = try await EngineFactory.start(choice: .auto, localeID: locale, options: options, capture: capture)
                // Closed or swapped while the recognizer was still starting (it may have to download a model first).
                if Task.isCancelled {
                    await started.engine.stop()
                    self?.endListening()
                    return
                }
                self?.dictationEngine = started.engine
                // A quiet moment ends it: never listen for more than a short answer.
                let timeout = Task { try? await Task.sleep(for: .seconds(12)); await started.engine.stop() }
                heard = try await ReplyHelper.firstUtterance(from: started.events)
                timeout.cancel()
                await started.engine.stop()
            } catch {
                if !Task.isCancelled { self?.phase = .failed(error.localizedDescription) }
            }
            guard let self else { return }
            endListening()
            if let heard, !Task.isCancelled {
                input = heard
                submit()
            }
        }
    }

    private func endListening() {
        dictationEngine = nil
        dictation = nil
        listening = false
        app.dictationActive = false
    }

    /// The mic button again: stop here and use what was heard so far. Before the recognizer is up there is nothing yet, so it is a cancel.
    func stopListening() {
        guard listening else { return }
        if let engine = dictationEngine {
            Task { await engine.stop() }
        } else {
            cancelListening()
        }
    }

    /// Closing the panel, swapping the direction or starting over: nothing keeps listening and nothing is translated.
    func cancelListening() {
        guard listening else { return }
        dictation?.cancel()
        let engine = dictationEngine
        endListening()
        Task { await engine?.stop() }
    }

    /// The panel closed.
    func closed() {
        cancelListening()
    }
}
