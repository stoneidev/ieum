import AppKit
import AVFoundation
import Combine
import Foundation
import IOKit
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
    @Published private(set) var partialSpeaker: Speaker?
    /// Finalized text that is still recent enough to belong on the subtitle bar.
    @Published private(set) var barFinalText = ""
    @Published private(set) var scriptFile: URL?
    /// Set when the transcript file can no longer be written; the captions keep working.
    @Published private(set) var transcriptWarning: String?

    // MARK: Meeting
    @Published private(set) var setup = Preferences.meetingSetup
    @Published private(set) var englishVariant = Preferences.englishVariant
    @Published private(set) var source = Preferences.source
    @Published private(set) var inputDeviceUID = Preferences.inputDeviceUID
    /// Shown while starting when a language model has to be downloaded first.
    @Published private(set) var startingNote: String?
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
    @Published private(set) var showsWordsSooner = Preferences.showsWordsSooner
    /// Result of the first-run test (see `runSelfTest`).
    @Published private(set) var selfTest: SelfTestState = .idle
    private var selfTestActive = false
    private var testVoice: Process?
    /// Set by the app delegate: the overlay's menu opens the windows it owns.
    var openSettings: () -> Void = {}
    var bringOverlayToFront: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var overlayIsCovered: () -> Bool = { false }
    var openSetup: () -> Void = {}
    @Published private(set) var clickThrough = Preferences.clickThrough
    @Published private(set) var keepsOnTop = Preferences.keepsOnTop
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
    private var corrector = VocabularyCorrector(terms: Preferences.vocabulary)

    var isRunning: Bool { status.isRunning }

    // MARK: Session control

    func start() {
        guard !isRunning else { return }
        // A saved mode that needs a newer macOS than this one cannot run; fall back before anything starts.
        if !source.isAvailableOnThisMac {
            source = .microphone
            Preferences.source = .microphone
        }
        if setup.bothWays, !MeetingSetup.bothWaysIsAvailableOnThisMac {
            setup = setup.speakingBothWays(false)
            Preferences.meetingSetup = setup
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
        status = .starting
        startingNote = nil
        transcriptWarning = nil
        let setup = activeSetup
        let locales = setup.recognitionLocales(englishLocale: englishVariant.rawValue)
        let source = self.source
        let vocabulary = self.vocabulary
        let deviceUID = InputDevices.resolve(preferredUID: inputDeviceUID, available: InputDevices.available())
        sessionTask = Task { [weak self] in
            await self?.runSession(setup: setup, locales: locales, source: source, deviceUID: deviceUID, vocabulary: vocabulary)
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

    // MARK: First-run test

    /// Plays a short English sentence through the speakers and checks that this Mac hears it, recognizes it and translates it.
    /// A new user learns in seconds that everything works, instead of finding out in the middle of a meeting. It runs the
    /// real pipeline (English to Korean, microphone) and then puts the saved mode and source back; nothing is saved.
    func runSelfTest() {
        guard !isRunning, selfTest != .running else { return }
        selfTest = .running
        Task { await performSelfTest() }
    }

    private func performSelfTest() async {
        let savedSetup = setup, savedSource = source
        selfTestActive = true
        setup = MeetingSetup(heard: .english, shown: .korean)
        source = .microphone
        updateSecondaryRow()
        let firstNewLine = finalizedLines.count
        start()

        func wait(upTo seconds: Double, until done: () -> Bool) async {
            var waited = 0.0
            while !done(), waited < seconds {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 0.1
            }
        }

        await wait(upTo: 20) { status != .starting }
        var result: SelfTestState
        if status == .listening {
            // `say` plays through the same speakers the meeting would; AVSpeechSynthesizer stayed silent in this agent-style app.
            let voice = AVSpeechSynthesisVoice(language: "en-US")?.name
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = (voice.map { ["-v", $0] } ?? []) + ["-r", "170", "Hello. This is a test. Can you see these words on your screen?"]
            testVoice = (try? say.run()) != nil ? say : nil
            // The sentence takes about four seconds. Stopping flushes the recognizer, so a sentence it was still holding open
            // is delivered and translated (stop waits a moment for the translations of the last sentences).
            await wait(upTo: 14) { !(testVoice?.isRunning ?? false) }
            await wait(upTo: 2.5) { false }
            testVoice?.terminate()
            testVoice = nil
            await stop()
            let lines = Array(finalizedLines.dropFirst(firstNewLine))
            if lines.isEmpty {
                result = .failed(Self.lidIsClosed
                    ? tr("Nothing was heard: the MacBook lid is closed, which turns its built-in microphone off. Open the lid or use an external microphone, then try again.",
                         "아무것도 들리지 않았습니다. MacBook 덮개가 닫혀 있으면 내장 마이크가 꺼집니다. 덮개를 열거나 외장 마이크를 쓴 뒤 다시 시도하세요.")
                    : tr("Nothing was heard. Turn the volume up and take off headphones (the microphone has to hear the speakers), then try again.",
                         "아무것도 들리지 않았습니다. 소리를 키우고 헤드폰을 벗은 뒤(마이크가 스피커 소리를 들어야 합니다) 다시 시도하세요."))
            } else {
                let heard = TextScript.join(lines.map(\.text))
                let translated = TextScript.join(lines.compactMap(\.translation))
                result = .passed(heard: heard, translation: translated.isEmpty ? nil : translated)
            }
        } else if case .error(let message) = status {
            result = .failed(message)
        } else {
            result = .failed(tr("Captions could not start.", "자막을 시작하지 못했습니다."))
        }
        await stop()   // no-op when already stopped
        finalizedLines.removeSubrange(firstNewLine...)
        barEntries.removeAll()
        barFinalText = ""
        barTranslation = ("", "")
        setup = savedSetup
        source = savedSource
        updateSecondaryRow()
        selfTestActive = false
        selfTest = result
    }

    /// A closed MacBook lid (clamshell mode with an external display) switches the built-in microphone off.
    private static var lidIsClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (state as? Bool) ?? false
    }

    // MARK: Settings: meeting

    /// The language that is recognized. Choosing the language that is shown swaps the two.
    func setHeard(_ language: SpokenLanguage) { apply(setup.hearing(language)) }

    /// The language to read; nil shows captions only. Choosing the language that is heard swaps the two.
    func setShown(_ language: SpokenLanguage?) { apply(setup.showing(language)) }

    /// Both sides speak: each sentence is recognized in whichever language it was said in and translated into the other.
    func setBothWays(_ on: Bool) {
        guard !on || MeetingSetup.bothWaysIsAvailableOnThisMac else { return }
        apply(setup.speakingBothWays(on))
    }

    /// Manual fallback for the language direction, and a quick correction in any case.
    func swapDirection() { apply(setup.swapped) }

    private func apply(_ new: MeetingSetup) {
        guard new != setup else { return }
        let carriesOn = new.runsLike(setup)
        setup = new
        Preferences.meetingSetup = new
        updateSecondaryRow()
        if !carriesOn { restartIfRunning() }
    }

    func setEnglishVariant(_ language: Language) {
        guard language != englishVariant, language != .korean else { return }
        englishVariant = language
        Preferences.englishVariant = language
        if setup.recognizesEnglish { restartIfRunning() }
    }

    func setSource(_ new: Source) {
        guard new != source else { return }
        source = new
        Preferences.source = new
        restartIfRunning()
    }

    func setInputDevice(_ uid: String?) {
        guard uid != inputDeviceUID else { return }
        inputDeviceUID = uid
        Preferences.inputDeviceUID = uid
        if source != .system { restartIfRunning() }
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

    /// One step smaller or larger; stops at the ends of the scale.
    func stepTextSize(by delta: Int) {
        let all = TextSize.allCases
        guard let index = all.firstIndex(of: textSize), all.indices.contains(index + delta) else { return }
        setTextSize(all[index + delta])
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

    /// The show/hide shortcut. When the captions can sit behind other windows and one covers them, it brings them forward
    /// instead of hiding what the person is trying to see.
    func toggleOverlayVisible() {
        if overlayVisible, !keepsOnTop, overlayIsCovered() {
            bringOverlayToFront()
            return
        }
        overlayVisible.toggle()
    }

    func setKeepsOnTop(_ on: Bool) {
        keepsOnTop = on
        Preferences.keepsOnTop = on
    }

    // MARK: Settings: behavior

    /// Takes effect the next time captions start.
    func setShowsWordsSooner(_ on: Bool) {
        showsWordsSooner = on
        Preferences.showsWordsSooner = on
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
            let tag = line.speaker.map { "[\($0.rawValue.uppercased())] " } ?? (activeSetup.isConversation && !line.language.isEmpty ? "[\(line.language.uppercased())] " : "")
            var text = "[\(formatter.string(from: line.time))] \(tag)\(line.text)"
            if let translation = line.translation { text += "\n[\(formatter.string(from: line.time))] → \(translation)" }
            return text
        }.joined(separator: "\n")
    }

    // MARK: Translation

    private func updateSecondaryRow() {
        let wanted = activeSetup.translates && (translationLayout == .both || translationNotice != nil)
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
        guard isRunning, !stopRequested, activeSetup.translates else {
            updateSecondaryRow()
            return
        }
        var ready: [String: (final: any TextTranslator, interim: any TextTranslator)] = [:]
        var failures: [String] = []
        for pair in activeSetup.translationPairs {
            // Sentences that just ended get a translator of their own, so they never wait behind the interim one.
            let finals = await SystemTranslation.makeTranslator(from: pair.source, to: pair.target)
            let interims = await SystemTranslation.makeTranslator(from: pair.source, to: pair.target)
            switch (finals, interims) {
            case (.success(let final), .success(let interim)): ready[pair.source] = (final, interim)
            case (.failure(let reason), _), (_, .failure(let reason)): failures.append(reason.localizedMessage)
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
            recorder?.appendTranslation(translation, forSentenceAt: line.time, targetLanguage: activeSetup.translationTarget(forSpeechIn: line.language), speaker: line.speaker)
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

    private func runSession(setup: MeetingSetup, locales: [String], source: Source, deviceUID: String?, vocabulary: [String]) async {
        let capture: any AudioCapture = source == .microphone ? MicrophoneCapture(deviceUID: deviceUID) : SystemAudioCapture()
        let isCall = source == .call
        var failure: String?
        var recoverable = false
        let missing = await ModernSpeechSupport.uninstalledLocales(locales)
        if !missing.isEmpty, status == .starting {
            let names = missing.compactMap { SpokenLanguage(code: $0)?.name }.joined(separator: ", ")
            startingNote = tr("Downloading the \(names) speech model (one time, needs internet)…", "\(names) 음성 모델을 내려받는 중 (처음 한 번, 인터넷 필요)…")
        }
        do {
            let directory = Preferences.scriptDirectory
            do {
                // The first-run test leaves no transcript behind.
                recorder = selfTestActive ? nil : try ScriptRecorder(
                    directory: directory, locale: isCall ? "call" : (setup.isConversation ? "conversation" : locales[0]),
                    tagLanguages: setup.isConversation && !isCall, tagSpeakers: isCall
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
            // Closing a sentence at a pause makes the English recognizer mangle the first words of the next sentence
            // (word error rate 7 % became 15 to 20 % on speech with pauses), and on its own it already closes English
            // sentences about 0.9 s after the speaker stops. Korean needs the pause (its sentences stay open for about
            // 2.6 s), and so does conversation mode, whose language decision waits for finished sentences.
            if !setup.isConversation, locales[0].hasPrefix("en") { options.pauseFinalization = nil }
            let started: (engine: any TranscriberEngine, events: AsyncThrowingStream<TranscriptionEvent, Error>)
            if isCall {
                // Echo cancellation keeps the other side's voice, played through the speakers, out of the microphone. It only
                // works on the default input, so a microphone chosen in Settings is used as it is and EchoGuard filters the leak.
                let call = CallEngine(
                    theirLocale: locale(for: setup.heard), myLocale: locale(for: setup.shown ?? setup.heard),
                    options: options, microphone: MicrophoneCapture(voiceProcessing: deviceUID == nil, deviceUID: deviceUID)
                )
                started = (call, try await call.events(from: capture))
            } else if setup.isConversation {
                started = try await EngineFactory.startConversation(locales: locales, options: options, capture: capture)
            } else {
                started = try await EngineFactory.start(choice: .auto, localeID: locales[0], options: options, capture: capture)
            }
            engine = started.engine
            if stopRequested {
                await started.engine.stop()
            } else {
                status = .listening
                listeningSince = Date()
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

    /// Asks for a name for the transcript of the meeting that just ended ("Budget meeting") and renames the file and its exports.
    func renameLastTranscript() {
        guard !isRunning, let url = scriptFile, FileManager.default.fileExists(atPath: url.path) else { return }
        let alert = NSAlert()
        alert.messageText = tr("Name this meeting", "이 회의에 이름 붙이기")
        alert.informativeText = tr("The transcript and the subtitle files made from it take this name.", "기록과 그 기록에서 만든 자막 파일의 이름이 됩니다.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = url.deletingPathExtension().lastPathComponent
        alert.accessoryView = field
        alert.addButton(withTitle: tr("Rename", "이름 바꾸기"))
        alert.addButton(withTitle: tr("Cancel", "취소"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if let renamed = try TranscriptFiles.rename(url, to: field.stringValue) { scriptFile = renamed }
        } catch {
            let failure = NSAlert()
            failure.messageText = tr("Could not rename the transcript", "기록의 이름을 바꾸지 못했습니다")
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    func transcriptMoved(to url: URL) { scriptFile = url }

    /// Whether there is a finished transcript from this run of the app that can be named.
    var canNameLastTranscript: Bool { !isRunning && scriptFile.map { FileManager.default.fileExists(atPath: $0.path) } == true }

    /// The setup the engines run. In a call both sides are recognized, each in its own language, so both directions are translated.
    var activeSetup: MeetingSetup { source == .call && setup.translates ? setup.speakingBothWays(true) : setup }

    private func locale(for language: SpokenLanguage) -> String {
        language == .english ? englishVariant.rawValue : language.defaultLocale
    }

    /// When the first audio of this listening run was heard; the clock for `spokenTime`.
    private var listeningSince: Date?

    /// When a sentence was said: the start of the audio plus where in it the sentence begins. Its arrival time is much
    /// later, because a recognizer reports a sentence only after it ended (Korean and Japanese sentences stay open for
    /// about 15 seconds), and the transcript is for finding the moment again.
    private func spokenTime(_ event: TranscriptionEvent) -> Date {
        guard let start = event.audioStart, start >= 0, let since = listeningSince else { return event.timestamp }
        return min(since.addingTimeInterval(start), event.timestamp)
    }

    private func apply(_ event: TranscriptionEvent) {
        let text = corrector.correct(RepetitionGuard.collapse(TranscriptCleaner.clean(event.text)))
        let language = String(event.locale.prefix(2))
        if event.isFinal {
            let provisional = translatedPartial.isEmpty ? nil : translatedPartial
            partial = ""
            translatedPartial = ""
            guard !text.isEmpty else { return }
            let spoken = spokenTime(event)
            var line = TranscriptLine(time: spoken, text: text)
            line.language = language
            line.speaker = event.speaker
            line.session = sessionIndex
            line.provisional = translationActive ? provisional : nil
            finalizedLines.append(line)
            if finalizedLines.count > Self.maxLines { finalizedLines.removeFirst(finalizedLines.count - Self.maxLines) }
            barEntries.append(BarEntry(id: line.id, time: event.timestamp, text: text))
            refreshBar()
            recorder?.append(TranscriptionEvent(text: text, isFinal: true, locale: event.locale, timestamp: spoken, speaker: event.speaker))
            if pipelines[language] != nil { awaitingTranslation.insert(line.id) }
            feed?.yield(.final(line.id, text, language: language))
        } else {
            if partialLanguage != language { partialLanguage = language; translatedPartial = "" }
            partialSpeaker = event.speaker
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
    }

    private func refreshBar() {
        let cutoff = Date().addingTimeInterval(-Self.barLinger)
        barEntries.removeAll { $0.time < cutoff }
        let recent = barEntries.suffix(3)
        let text = TextScript.join(recent.map(\.text))
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
        let value = (TextScript.join(confirmed), TextScript.join(tentative))
        if value != barTranslation { barTranslation = value }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? EngineError, let message = error.errorDescription { return message }
        return tr("Something went wrong: \(error.localizedDescription)", "문제가 생겼습니다: \(error.localizedDescription)")
    }
}
