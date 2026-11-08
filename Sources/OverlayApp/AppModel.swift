import AppKit
import Combine
import Foundation
import CaptionCore

/// Everything the overlay, the menu and the settings show, plus the recognition session that feeds them.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Session state
    @Published private(set) var status: SessionStatus = .idle
    @Published private(set) var finalizedLines: [TranscriptLine] = []
    @Published private(set) var partial = ""
    /// Language ("en" / "ko") of the sentence being spoken.
    @Published private(set) var partialLanguage = ""
    /// Finalized text that is still recent enough to belong on the subtitle bar.
    @Published private(set) var barFinalText = ""
    @Published private(set) var scriptFile: URL?
    @Published private(set) var isQuiet = false
    /// Set when the transcript file can no longer be written; the captions keep working.
    @Published private(set) var transcriptWarning: String?

    // MARK: Meeting
    @Published private(set) var meetingMode = Preferences.meetingMode
    @Published private(set) var englishVariant = Preferences.englishVariant
    @Published private(set) var captionLanguage = Preferences.captionLanguage
    @Published private(set) var source = Preferences.source
    @Published private(set) var vocabulary = Preferences.vocabulary

    // MARK: Display
    @Published private(set) var displayMode = Preferences.displayMode
    @Published private(set) var barLines = Preferences.barLines
    @Published private(set) var textSize = Preferences.textSize
    @Published private(set) var background = Preferences.background
    @Published private(set) var backgroundOpacity = Preferences.backgroundOpacity
    @Published private(set) var translationLayout = Preferences.translationLayout
    @Published private(set) var overlayVisible = true

    // MARK: Behavior
    @Published private(set) var fadeWhenQuiet = Preferences.fadeWhenQuiet
    @Published private(set) var showsWordsSooner = Preferences.showsWordsSooner
    @Published private(set) var clickThrough = Preferences.clickThrough
    @Published private(set) var globalShortcuts = Preferences.globalShortcuts
    @Published private(set) var uiLanguage = Preferences.uiLanguage

    // MARK: Translation
    /// True while a translator is ready, so the translation (not the original) is the main text.
    @Published private(set) var translationActive = false
    /// Why translation cannot be used right now, in words the user can act on.
    @Published private(set) var translationNotice: String?
    /// Latest interim translation of the sentence being spoken.
    @Published private(set) var translatedPartial = ""
    /// Recent sentences' translations for the bar: `confirmed` is final, `tentative` may still change.
    @Published private(set) var barTranslation = (confirmed: "", tentative: "")
    /// The small original-language row above the translation.
    @Published private(set) var showsSecondaryRow = false

    /// How long a finalized sentence stays on the bar after the last speech.
    static let barLinger: TimeInterval = 12
    /// How long the overlay waits in silence before it fades.
    static let fadeDelay: TimeInterval = 6
    private static let maxLines = 5000

    private struct BarEntry {
        let id: UUID
        let time: Date
        let text: String
    }

    private enum Feed {
        case interim(String, language: String)
        case final(UUID, String, language: String)
    }

    private var barEntries: [BarEntry] = []
    private var sessionTask: Task<Void, Never>?
    private var engine: (any TranscriberEngine)?
    private var recorder: ScriptRecorder?
    private var stopRequested = false
    private var pruneTask: Task<Void, Never>?
    private var pipelines: [String: TranslationPipeline] = [:]
    private var feed: AsyncStream<Feed>.Continuation?
    private var translationTasks: [Task<Void, Never>] = []
    /// Bumped whenever translation is reconfigured or torn down, so a configure that was suspended while the
    /// translators were prepared can tell it is out of date and must not start anything.
    private var translationGeneration = 0
    private var sessionIndex = 0
    private var showsFailureNotice = false
    /// Finalized sentences handed to the translators whose translation has not come back yet.
    private var awaitingTranslation = Set<UUID>()
    private var autoRestarts: [Date] = []
    private var autoRestartTask: Task<Void, Never>?
    private var lastActivity = Date()
    private var corrector = VocabularyCorrector(terms: Preferences.vocabulary)

    var isRunning: Bool { status.isRunning }

    // MARK: Session control

    func start() {
        guard !isRunning else { return }
        // A saved mode that needs a newer macOS than this one cannot run; fall back before anything starts.
        if !meetingMode.isAvailableOnThisMac {
            meetingMode = .englishToKorean
            Preferences.meetingMode = .englishToKorean
            updateSecondaryRow()
        }
        stopRequested = false
        sessionIndex += 1
        // Nothing from the previous session (or mode) may linger on the bar.
        barEntries.removeAll()
        barFinalText = ""
        barTranslation = ("", "")
        translatedPartial = ""
        partial = ""
        lastActivity = Date()
        status = .starting
        transcriptWarning = nil
        let mode = meetingMode
        let locales = mode.recognitionLocales(englishLocale: englishVariant.rawValue, captionLocale: captionLanguage.rawValue)
        let source = self.source
        let vocabulary = self.vocabulary
        sessionTask = Task { [weak self] in
            await self?.runSession(mode: mode, locales: locales, source: source, vocabulary: vocabulary)
        }
        startPruning()
    }

    /// Stops capture and waits until the recognizer has delivered its last results.
    func stop() async {
        // The user asked to stop: an automatic restart that is about to happen must not override that.
        autoRestartTask?.cancel()
        autoRestartTask = nil
        guard sessionTask != nil else { return }
        stopRequested = true
        await engine?.stop()
        await sessionTask?.value
    }

    func restart() async {
        await stop()
        start()
    }

    func toggleRunning() {
        if isRunning { Task { await stop() } } else { start() }
    }

    private func restartIfRunning() {
        if isRunning { Task { await restart() } }
    }

    // MARK: Settings: meeting

    func setMeetingMode(_ mode: MeetingMode) {
        guard mode != meetingMode, mode.isAvailableOnThisMac else { return }
        meetingMode = mode
        Preferences.meetingMode = mode
        updateSecondaryRow()
        restartIfRunning()
    }

    /// Manual fallback for the language direction: flips English → Korean and Korean → English. Handy when
    /// automatic conversation mode is not available, and as a quick correction in any case.
    func swapDirection() {
        switch meetingMode {
        case .englishToKorean: setMeetingMode(.koreanToEnglish)
        case .koreanToEnglish: setMeetingMode(.englishToKorean)
        case .conversation, .captionsOnly: setMeetingMode(.englishToKorean)
        }
    }

    func setEnglishVariant(_ language: Language) {
        guard language != englishVariant, language != .korean else { return }
        englishVariant = language
        Preferences.englishVariant = language
        if meetingMode != .koreanToEnglish && meetingMode != .captionsOnly { restartIfRunning() }
    }

    func setCaptionLanguage(_ language: Language) {
        guard language != captionLanguage else { return }
        captionLanguage = language
        Preferences.captionLanguage = language
        if meetingMode == .captionsOnly { restartIfRunning() }
    }

    func setSource(_ new: Source) {
        guard new != source else { return }
        source = new
        Preferences.source = new
        restartIfRunning()
    }

    /// One term per element. Applies to the very next sentence: the correction runs on the text, so no restart.
    func setVocabulary(_ terms: [String]) {
        let cleaned = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard cleaned != vocabulary else { return }
        vocabulary = cleaned
        Preferences.vocabulary = cleaned
        corrector = VocabularyCorrector(terms: cleaned)
    }

    // MARK: Settings: display

    func setDisplayMode(_ new: DisplayMode) {
        displayMode = new
        Preferences.displayMode = new
    }

    func cycleDisplayMode() {
        setDisplayMode(displayMode == .bar ? .panel : .bar)
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

    func setTranslationLayout(_ layout: TranslationLayout) {
        translationLayout = layout
        Preferences.translationLayout = layout
        updateSecondaryRow()
    }

    func toggleOverlayVisible() { overlayVisible.toggle() }

    // MARK: Settings: behavior

    /// Takes effect the next time captions start.
    func setShowsWordsSooner(_ on: Bool) {
        showsWordsSooner = on
        Preferences.showsWordsSooner = on
    }

    func setFadeWhenQuiet(_ on: Bool) {
        fadeWhenQuiet = on
        Preferences.fadeWhenQuiet = on
        if !on { isQuiet = false }
    }

    func setClickThrough(_ on: Bool) {
        clickThrough = on
        Preferences.clickThrough = on
    }

    func setGlobalShortcuts(_ on: Bool) {
        globalShortcuts = on
        Preferences.globalShortcuts = on
    }

    func setUILanguage(_ choice: String) {
        uiLanguage = choice
        Preferences.uiLanguage = choice
        L10n.choice = choice
        // Views re-read their text because `uiLanguage` is published.
    }

    func setScriptDirectory(_ url: URL) {
        Preferences.scriptDirectory = url
        objectWillChange.send()
    }

    func transcriptText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return finalizedLines.map { line in
            let tag = meetingMode.isConversation && !line.language.isEmpty ? "[\(line.language.uppercased())] " : ""
            var text = "[\(formatter.string(from: line.time))] \(tag)\(line.text)"
            if let translation = line.translation { text += "\n[\(formatter.string(from: line.time))] → \(translation)" }
            return text
        }.joined(separator: "\n")
    }

    // MARK: Translation

    private func updateSecondaryRow() {
        let wanted = meetingMode.translates && (translationLayout == .both || translationNotice != nil)
        if wanted != showsSecondaryRow { showsSecondaryRow = wanted }
    }

    /// (Re)builds the translators the current mode needs. Safe to call at any time, also while listening.
    private func configureTranslation() async {
        translationGeneration += 1
        let generation = translationGeneration
        let old = cancelTranslation()
        translationNotice = nil
        showsFailureNotice = false
        for pipeline in old { await pipeline.close() }
        guard generation == translationGeneration else { return }
        guard isRunning, !stopRequested, meetingMode.translates else {
            updateSecondaryRow()
            return
        }
        var ready: [String: (final: any TextTranslator, interim: any TextTranslator)] = [:]
        var failures: [String] = []
        for pair in meetingMode.translationPairs {
            // Sentences that just ended get a translator of their own, so they never wait behind the interim one.
            let finals = await SystemTranslation.makeTranslator(from: pair.source, to: pair.target)
            let interims = await SystemTranslation.makeTranslator(from: pair.source, to: pair.target)
            switch (finals, interims) {
            case (.success(let final), .success(let interim)): ready[pair.source] = (final, interim)
            case (.failure(let reason), _), (_, .failure(let reason)): failures.append(reason.message)
            }
            // A newer configure, a stop, or the end of the session may have happened while this one was preparing.
            guard generation == translationGeneration, isRunning, !stopRequested else { return }
        }
        if !ready.isEmpty { startTranslation(ready) }
        translationNotice = failures.first
        updateSecondaryRow()
    }

    private func startTranslation(_ translators: [String: (final: any TextTranslator, interim: any TextTranslator)]) {
        var made: [String: TranslationPipeline] = [:]
        for (language, pair) in translators { made[language] = TranslationPipeline(translator: pair.final, interimTranslator: pair.interim) }
        pipelines = made
        // One consumer feeds the pipelines, so interim and final submissions keep the order they happened in.
        let (stream, continuation) = AsyncStream.makeStream(of: Feed.self, bufferingPolicy: .unbounded)
        feed = continuation
        var tasks: [Task<Void, Never>] = [
            Task {
                for await item in stream {
                    switch item {
                    case .interim(let text, let language): await made[language]?.submitInterim(text)
                    case .final(let id, let text, let language): await made[language]?.submitFinal(id: id, text: text)
                    }
                }
            },
        ]
        for pipeline in made.values {
            tasks.append(Task { [weak self] in
                for await output in pipeline.outputs { self?.handle(output) }
            })
        }
        translationTasks = tasks
        translationActive = true
        // Sentences that were finalized before the translators were ready still get translated.
        for line in finalizedLines where line.translation == nil && line.session == sessionIndex {
            continuation.yield(.final(line.id, line.text, language: line.language))
        }
        if !partial.isEmpty { continuation.yield(.interim(partial, language: partialLanguage)) }
    }

    /// Synchronously detaches the current pipelines (so nothing more reaches the model from them) and returns them to be closed.
    private func cancelTranslation() -> [TranslationPipeline] {
        feed?.finish()
        feed = nil
        translationTasks.forEach { $0.cancel() }
        translationTasks = []
        let old = Array(pipelines.values)
        pipelines = [:]
        awaitingTranslation.removeAll()
        translationActive = false
        translatedPartial = ""
        refreshBar()
        return old
    }

    private func tearDownTranslation() async {
        translationGeneration += 1
        for pipeline in cancelTranslation() { await pipeline.close() }
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
            awaitingTranslation.remove(id)
            guard let index = finalizedLines.firstIndex(where: { $0.id == id }) else { return }
            finalizedLines[index].translation = translation
            finalizedLines[index].provisional = nil
            clearFailureNotice()
            let line = finalizedLines[index]
            recorder?.appendTranslation(translation, forSentenceAt: line.time, targetLanguage: meetingMode.translationTarget(forSpeechIn: line.language))
            refreshBar()
        case .failed(let id, let message):
            // A slow interim translation is just skipped: the next one replaces it. Only a sentence that never got
            // its translation is worth telling the user about.
            guard let id else { return }
            awaitingTranslation.remove(id)
            translationNotice = tr("Translation failed: \(message)", "번역 실패: \(message)")
            showsFailureNotice = true
            updateSecondaryRow()
            if let index = finalizedLines.firstIndex(where: { $0.id == id }) { finalizedLines[index].provisional = nil }
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

    private func runSession(mode: MeetingMode, locales: [String], source: Source, vocabulary: [String]) async {
        let capture: any AudioCapture = source == .microphone ? MicrophoneCapture() : SystemAudioCapture()
        var failure: String?
        var recoverable = false
        do {
            let directory = Preferences.scriptDirectory
            do {
                recorder = try ScriptRecorder(
                    directory: directory, locale: mode.isConversation ? "conversation" : locales[0], tagLanguages: mode.isConversation
                )
            } catch {
                throw EngineError.captureFailed(
                    tr("Can't save transcripts to \(directory.path). Choose another folder in Settings, then start again.",
                       "\(directory.path)에 기록을 저장할 수 없습니다. 설정에서 다른 폴더를 고른 뒤 다시 시작하세요.")
                )
            }
            recorder?.onFailure { [weak self] reason in
                Task { @MainActor in
                    self?.transcriptWarning = tr("The transcript can no longer be saved (\(reason)). Captions keep running.",
                                                 "기록을 더 이상 저장할 수 없습니다(\(reason)). 자막은 계속 나옵니다.")
                }
            }
            scriptFile = recorder?.fileURL

            var options = EngineOptions(vocabulary: vocabulary)
            options.correctsTranscript = false
            options.showsWordsSooner = showsWordsSooner
            let started = mode.isConversation
                ? try await EngineFactory.startConversation(locales: locales, options: options, capture: capture)
                : try await EngineFactory.start(choice: .auto, localeID: locales[0], options: options, capture: capture)
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
            // The events ended without the user asking for it: the audio source went away.
            if !stopRequested {
                if let reason = (capture as? SystemAudioCapture)?.failureMessage {
                    failure = tr("System audio stopped (\(reason)). It cannot be captured while the display is asleep or its source changed. Start captions again.",
                                 "시스템 소리 입력이 멈췄습니다(\(reason)). 디스플레이가 꺼졌거나 소리 출력이 바뀌면 캡처할 수 없습니다. 자막을 다시 시작하세요.")
                } else {
                    failure = tr("Captions stopped because the audio input ended. Start captions again.",
                                 "소리 입력이 끝나서 자막이 멈췄습니다. 자막을 다시 시작하세요.")
                }
            }
        } catch {
            failure = Self.describe(error)
            // The speech recognizer itself gave up (it does that now and then); starting over fixes it.
            recoverable = (error as NSError).domain == "SFSpeechErrorDomain"
        }
        // The last sentences are only just final: give their translations a moment before the translators close.
        await finishTranslation()
        recorder?.close()
        recorder = nil
        engine = nil
        sessionTask = nil
        pruneTask?.cancel()
        pruneTask = nil
        isQuiet = false
        // A recognizer error while winding down is not worth showing; the user already asked to stop.
        status = failure != nil && !stopRequested ? .error(failure ?? "") : .idle
        if status == .idle { partial = "" }
        if recoverable, !stopRequested, allowAutoRestart() {
            status = .idle
            autoRestartTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.start()
            }
        }
    }

    /// At most three automatic restarts in two minutes, so a persistent problem is shown instead of looping.
    private func allowAutoRestart() -> Bool {
        let now = Date()
        autoRestarts = autoRestarts.filter { now.timeIntervalSince($0) < 120 }
        guard autoRestarts.count < 3 else { return false }
        autoRestarts.append(now)
        return true
    }

    /// Waits (bounded) for the translations of sentences that just ended, then closes the translators.
    private func finishTranslation() async {
        let deadline = Date().addingTimeInterval(2.5)
        while !awaitingTranslation.isEmpty, pipelines.isEmpty == false, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await tearDownTranslation()
    }

    private func apply(_ event: TranscriptionEvent) {
        let text = corrector.correct(RepetitionGuard.collapse(event.text.trimmingCharacters(in: .whitespacesAndNewlines)))
        let language = String(event.locale.prefix(2))
        if !text.isEmpty { lastActivity = Date() }
        if isQuiet { isQuiet = false }
        if event.isFinal {
            let provisional = translatedPartial.isEmpty ? nil : translatedPartial
            partial = ""
            translatedPartial = ""
            guard !text.isEmpty else { return }
            var line = TranscriptLine(time: event.timestamp, text: text)
            line.language = language
            line.session = sessionIndex
            line.provisional = translationActive ? provisional : nil
            finalizedLines.append(line)
            if finalizedLines.count > Self.maxLines { finalizedLines.removeFirst(finalizedLines.count - Self.maxLines) }
            barEntries.append(BarEntry(id: line.id, time: event.timestamp, text: text))
            refreshBar()
            recorder?.append(TranscriptionEvent(text: text, isFinal: true, locale: event.locale, timestamp: event.timestamp))
            if pipelines[language] != nil { awaitingTranslation.insert(line.id) }
            feed?.yield(.final(line.id, text, language: language))
        } else {
            if partialLanguage != language { partialLanguage = language; translatedPartial = "" }
            partial = text
            feed?.yield(.interim(text, language: language))
        }
    }

    // MARK: Bar text and fading

    private func startPruning() {
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        refreshBar()
        let quiet = fadeWhenQuiet && status == .listening && Date().timeIntervalSince(lastActivity) > Self.fadeDelay
        if quiet != isQuiet { isQuiet = quiet }
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
        return tr("Something went wrong: \(error.localizedDescription)", "문제가 생겼습니다: \(error.localizedDescription)")
    }
}
