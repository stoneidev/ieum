import AppKit
import Combine
import Foundation
import MacSTTCore

enum Language: String, CaseIterable {
    case englishUS = "en-US"
    case englishAU = "en-AU"
    case korean = "ko-KR"

    var title: String {
        switch self {
        case .englishUS: "English (US)"
        case .englishAU: "English (Australia)"
        case .korean: "한국어"
        }
    }
}

enum Source: String, CaseIterable {
    case microphone
    case system

    var title: String { self == .microphone ? "Microphone" : "System audio" }
}

enum DisplayMode: String, CaseIterable {
    case bar
    case panel

    var title: String { self == .bar ? "Subtitle bar" : "Transcript panel" }
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
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }
}

enum BackgroundStyle: String, CaseIterable {
    case glass
    case solid
    case black
    case light

    var title: String {
        switch self {
        case .glass: "Smoked glass"
        case .solid: "Solid dark"
        case .black: "Black, white text"
        case .light: "Light"
        }
    }
}

enum TranslationTarget: String, CaseIterable {
    case off
    case korean
    case english

    var title: String {
        switch self {
        case .off: "Off"
        case .korean: "Korean (한국어)"
        case .english: "English"
        }
    }
    /// BCP-47 language code handed to the translation framework.
    var code: String? {
        switch self {
        case .off: nil
        case .korean: "ko"
        case .english: "en"
        }
    }
}

enum TranslationLayout: String, CaseIterable {
    case both
    case translationOnly

    var title: String { self == .both ? "Original and translation" : "Translation only" }
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
    /// Final translation of `text`, once the translator has delivered it.
    var translation: String?
    /// The last interim translation, shown (muted) until the final one arrives so the line never goes blank.
    var provisional: String?

    /// Which listening session produced this line; only the current session is back-filled with translations.
    var session = 0

    var displayTranslation: String? { translation ?? provisional }
}

/// User choices that survive relaunch. Launch arguments such as `-language ko-KR` override them for a run.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static var language: Language {
        get { Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .englishUS }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }
    static var source: Source {
        get { Source(rawValue: defaults.string(forKey: "source") ?? "") ?? .microphone }
        set { defaults.set(newValue.rawValue, forKey: "source") }
    }
    static var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .bar }
        set { defaults.set(newValue.rawValue, forKey: "displayMode") }
    }
    static var autoStart: Bool { defaults.bool(forKey: "autoStart") }

    static let lineChoices = [1, 2, 3, 4]
    static var barLines: Int {
        get {
            let value = defaults.integer(forKey: "barLines")
            return lineChoices.contains(value) ? value : 2
        }
        set { defaults.set(newValue, forKey: "barLines") }
    }
    static var textSize: TextSize {
        get { TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "textSize") }
    }
    static var background: BackgroundStyle {
        get { BackgroundStyle(rawValue: defaults.string(forKey: "background") ?? "") ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: "background") }
    }
    static var translationTarget: TranslationTarget {
        get { TranslationTarget(rawValue: defaults.string(forKey: "translationTarget") ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "translationTarget") }
    }
    static var translationLayout: TranslationLayout {
        get { TranslationLayout(rawValue: defaults.string(forKey: "translationLayout") ?? "") ?? .both }
        set { defaults.set(newValue.rawValue, forKey: "translationLayout") }
    }

    static let opacityRange = 0.2...1.0
    static var backgroundOpacity: Double {
        get {
            guard defaults.object(forKey: "backgroundOpacity") != nil else { return 0.8 }
            return min(max(defaults.double(forKey: "backgroundOpacity"), opacityRange.lowerBound), opacityRange.upperBound)
        }
        set { defaults.set(newValue, forKey: "backgroundOpacity") }
    }

    static var scriptDirectory: URL {
        get {
            if let path = defaults.string(forKey: "scriptDirectory"), !path.isEmpty { return URL(fileURLWithPath: path) }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documents.appendingPathComponent("STT Transcripts", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "scriptDirectory") }
    }
}

/// Everything the overlay and the menu show, plus the recognition session that feeds it.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: SessionStatus = .idle
    @Published private(set) var finalizedLines: [TranscriptLine] = []
    @Published private(set) var partial = ""
    /// Finalized text that is still recent enough to belong on the subtitle bar.
    @Published private(set) var barFinalText = ""
    @Published private(set) var scriptFile: URL?
    @Published var language: Language = Preferences.language
    @Published var source: Source = Preferences.source
    @Published var displayMode: DisplayMode = Preferences.displayMode
    @Published private(set) var barLines = Preferences.barLines
    @Published private(set) var textSize = Preferences.textSize
    @Published private(set) var background = Preferences.background
    @Published private(set) var backgroundOpacity = Preferences.backgroundOpacity

    // Translation
    @Published private(set) var translationTarget = Preferences.translationTarget
    @Published private(set) var translationLayout = Preferences.translationLayout
    /// True while a translator is ready, so the translation (not the original) is the main text.
    @Published private(set) var translationActive = false
    /// Why translation cannot be used right now, in words the user can act on.
    @Published private(set) var translationNotice: String?
    /// Latest interim translation of the sentence being spoken.
    @Published private(set) var translatedPartial = ""
    /// Recent sentences' translations for the bar: `confirmed` is final, `tentative` may still change.
    @Published private(set) var barTranslation = (confirmed: "", tentative: "")
    /// The small original-language row above the translation. It exists whenever translation is requested.
    @Published private(set) var showsSecondaryRow = false

    /// How long a finalized sentence stays on the bar after the last speech.
    static let barLinger: TimeInterval = 12
    private static let maxLines = 5000

    private struct BarEntry {
        let id: UUID
        let time: Date
        let text: String
    }

    private enum Feed {
        case interim(String)
        case final(UUID, String)
    }

    private var barEntries: [BarEntry] = []
    private var sessionTask: Task<Void, Never>?
    private var engine: (any TranscriberEngine)?
    private var recorder: ScriptRecorder?
    private var stopRequested = false
    private var pruneTask: Task<Void, Never>?
    private var pipeline: TranslationPipeline?
    private var feed: AsyncStream<Feed>.Continuation?
    private var translationTasks: [Task<Void, Never>] = []
    /// Bumped whenever translation is reconfigured or torn down, so a configure that was suspended while the
    /// translator was prepared can tell it is out of date and must not start anything.
    private var translationGeneration = 0
    private var sessionIndex = 0
    private var showsFailureNotice = false

    var isRunning: Bool { status.isRunning }

    // MARK: Session control

    func start() {
        guard !isRunning else { return }
        stopRequested = false
        sessionIndex += 1
        // Nothing from the previous session (or language) may linger on the bar.
        barEntries.removeAll()
        barFinalText = ""
        barTranslation = ("", "")
        translatedPartial = ""
        partial = ""
        status = .starting
        let language = self.language
        let source = self.source
        sessionTask = Task { [weak self] in
            await self?.runSession(language: language, source: source)
        }
        startPruning()
    }

    /// Stops capture and waits until the recognizer has delivered its last results.
    func stop() async {
        guard sessionTask != nil else { return }
        stopRequested = true
        await engine?.stop()
        await sessionTask?.value
    }

    func restart() async {
        await stop()
        start()
    }

    func setLanguage(_ new: Language) {
        guard new != language else { return }
        language = new
        Preferences.language = new
        if isRunning { Task { await restart() } }
    }

    func setSource(_ new: Source) {
        guard new != source else { return }
        source = new
        Preferences.source = new
        if isRunning { Task { await restart() } }
    }

    func setDisplayMode(_ new: DisplayMode) {
        displayMode = new
        Preferences.displayMode = new
    }

    func setBarLines(_ lines: Int) {
        barLines = lines
        Preferences.barLines = lines
    }

    func setTextSize(_ size: TextSize) {
        textSize = size
        Preferences.textSize = size
    }

    func setBackground(_ style: BackgroundStyle) {
        background = style
        Preferences.background = style
    }

    func setBackgroundOpacity(_ value: Double) {
        let clamped = min(max(value, Preferences.opacityRange.lowerBound), Preferences.opacityRange.upperBound)
        backgroundOpacity = clamped
        Preferences.backgroundOpacity = clamped
    }

    func setScriptDirectory(_ url: URL) {
        Preferences.scriptDirectory = url
    }

    func transcriptText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return finalizedLines.map { line in
            var text = "[\(formatter.string(from: line.time))] \(line.text)"
            if let translation = line.translation { text += "\n[\(formatter.string(from: line.time))] → \(translation)" }
            return text
        }.joined(separator: "\n")
    }

    // MARK: Translation

    func setTranslationTarget(_ target: TranslationTarget) {
        guard target != translationTarget else { return }
        translationTarget = target
        Preferences.translationTarget = target
        updateSecondaryRow()
        Task { await configureTranslation() }
    }

    func setTranslationLayout(_ layout: TranslationLayout) {
        translationLayout = layout
        Preferences.translationLayout = layout
        updateSecondaryRow()
    }

    private func updateSecondaryRow() {
        let wanted = translationTarget != .off && (translationLayout == .both || translationNotice != nil)
        if wanted != showsSecondaryRow { showsSecondaryRow = wanted }
    }

    /// (Re)builds the translator for the current language pair. Safe to call at any time, also while listening.
    private func configureTranslation() async {
        translationGeneration += 1
        let generation = translationGeneration
        let old = cancelTranslation()
        translationNotice = nil
        showsFailureNotice = false
        await old?.close()
        guard generation == translationGeneration else { return }
        guard isRunning, !stopRequested, let target = translationTarget.code else {
            updateSecondaryRow()
            return
        }
        let sourceCode = language == .korean ? "ko" : "en"
        guard sourceCode != target else {
            translationNotice = "Translation is on, but the speech is already in the target language."
            updateSecondaryRow()
            return
        }
        let result = await SystemTranslation.makeTranslator(from: sourceCode, to: target)
        // A newer configure, a stop, or the end of the session may have happened while this one was preparing.
        guard generation == translationGeneration, isRunning, !stopRequested else { return }
        switch result {
        case .failure(let reason):
            translationNotice = reason.message
            translationActive = false
        case .success(let translator):
            startTranslation(translator)
        }
        updateSecondaryRow()
    }

    private func startTranslation(_ translator: any TextTranslator) {
        let pipeline = TranslationPipeline(translator: translator)
        self.pipeline = pipeline
        // One consumer feeds the pipeline, so interim and final submissions keep the order they happened in.
        let (stream, continuation) = AsyncStream.makeStream(of: Feed.self, bufferingPolicy: .unbounded)
        feed = continuation
        translationTasks = [
            Task {
                for await item in stream {
                    switch item {
                    case .interim(let text): await pipeline.submitInterim(text)
                    case .final(let id, let text): await pipeline.submitFinal(id: id, text: text)
                    }
                }
            },
            Task { [weak self] in
                for await output in pipeline.outputs { self?.handle(output) }
            },
        ]
        translationActive = true
        // Sentences that were finalized before the translator was ready still get translated.
        for line in finalizedLines where line.translation == nil && line.session == sessionIndex {
            continuation.yield(.final(line.id, line.text))
        }
        if !partial.isEmpty { continuation.yield(.interim(partial)) }
    }

    /// Synchronously detaches the current pipeline (so nothing more reaches the model from it) and returns it to be closed.
    private func cancelTranslation() -> TranslationPipeline? {
        feed?.finish()
        feed = nil
        translationTasks.forEach { $0.cancel() }
        translationTasks = []
        let old = pipeline
        pipeline = nil
        translationActive = false
        translatedPartial = ""
        refreshBar()
        return old
    }

    private func tearDownTranslation() async {
        translationGeneration += 1
        await cancelTranslation()?.close()
    }

    private func handle(_ output: TranslationPipeline.Output) {
        switch output {
        case .interim(let source, let translation):
            // Only the sentence being spoken right now may show an interim translation. A result for the previous
            // sentence can still arrive just after the next one began; it does not match the current text.
            guard !partial.isEmpty, partial.hasPrefix(source) else { return }
            translatedPartial = translation
            clearFailureNotice()
            refreshBar()
        case .final(let id, let translation):
            guard let index = finalizedLines.firstIndex(where: { $0.id == id }) else { return }
            finalizedLines[index].translation = translation
            finalizedLines[index].provisional = nil
            clearFailureNotice()
            recorder?.appendTranslation(translation, forSentenceAt: finalizedLines[index].time)
            refreshBar()
        case .failed(let id, let message):
            // Keep the original on screen; just say what happened.
            translationNotice = "Translation failed: \(message)"
            showsFailureNotice = true
            updateSecondaryRow()
            if let id, let index = finalizedLines.firstIndex(where: { $0.id == id }) { finalizedLines[index].provisional = nil }
        }
    }

    /// A "translation failed" notice is temporary: it goes away as soon as translation works again.
    private func clearFailureNotice() {
        guard showsFailureNotice else { return }
        showsFailureNotice = false
        translationNotice = nil
        updateSecondaryRow()
    }

    // MARK: Session body

    private func runSession(language: Language, source: Source) async {
        let capture: any AudioCapture = source == .microphone ? MicrophoneCapture() : SystemAudioCapture()
        var failure: String?
        do {
            let directory = Preferences.scriptDirectory
            do {
                recorder = try ScriptRecorder(directory: directory, locale: language.rawValue)
            } catch {
                throw EngineError.captureFailed(
                    "Can't save transcripts to \(directory.path). Choose another folder from the menu bar (Choose transcript folder…), then start again."
                )
            }
            scriptFile = recorder?.fileURL

            let started = try await EngineFactory.start(
                choice: .auto, localeID: language.rawValue, options: EngineOptions(), capture: capture
            )
            engine = started.engine
            if stopRequested {
                await started.engine.stop()
            } else {
                status = .listening
                // Translation is prepared in the background so it never delays the first captions.
                Task { await configureTranslation() }
            }
            for try await event in started.events {
                apply(event)
            }
        } catch {
            failure = Self.describe(error)
        }
        await tearDownTranslation()
        recorder?.close()
        recorder = nil
        engine = nil
        sessionTask = nil
        pruneTask?.cancel()
        pruneTask = nil
        // A recognizer error while winding down is not worth showing; the user already asked to stop.
        status = failure != nil && !stopRequested ? .error(failure ?? "") : .idle
        if status == .idle { partial = "" }
    }

    private func apply(_ event: TranscriptionEvent) {
        let text = RepetitionGuard.collapse(event.text.trimmingCharacters(in: .whitespacesAndNewlines))
        if event.isFinal {
            let provisional = translatedPartial.isEmpty ? nil : translatedPartial
            partial = ""
            translatedPartial = ""
            guard !text.isEmpty else { return }
            var line = TranscriptLine(time: event.timestamp, text: text)
            line.session = sessionIndex
            line.provisional = translationActive ? provisional : nil
            finalizedLines.append(line)
            if finalizedLines.count > Self.maxLines { finalizedLines.removeFirst(finalizedLines.count - Self.maxLines) }
            barEntries.append(BarEntry(id: line.id, time: event.timestamp, text: text))
            refreshBar()
            recorder?.append(event)
            feed?.yield(.final(line.id, text))
        } else {
            partial = text
            feed?.yield(.interim(text))
        }
    }

    // MARK: Bar text

    private func startPruning() {
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshBar()
            }
        }
    }

    private func refreshBar() {
        let cutoff = Date().addingTimeInterval(-Self.barLinger)
        barEntries.removeAll { $0.time < cutoff }
        let recent = barEntries.suffix(3)
        let text = recent.map(\.text).joined(separator: " ")
        if text != barFinalText { barFinalText = text }

        // Confirmed translations come first; everything after the first unconfirmed sentence is tentative.
        var confirmed: [String] = []
        var tentative: [String] = []
        for entry in recent {
            let line = finalizedLines.last { $0.id == entry.id }
            if tentative.isEmpty, let final = line?.translation {
                confirmed.append(final)
            } else if let guess = line?.displayTranslation {
                tentative.append(guess)
            }
        }
        if !translatedPartial.isEmpty { tentative.append(translatedPartial) }
        let value = (confirmed.joined(separator: " "), tentative.joined(separator: " "))
        if value != barTranslation { barTranslation = value }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? EngineError, let message = error.errorDescription { return message }
        return "Something went wrong: \(error.localizedDescription)"
    }
}
