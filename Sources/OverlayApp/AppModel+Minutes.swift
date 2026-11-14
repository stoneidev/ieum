import CaptionCore
import Foundation

/// The minutes draft of the meeting that just ended, made from the saved transcript and shown in the panel.
extension AppModel {
    /// The language the minutes are written in: the one the person reads, else the one that was heard.
    var minutesLanguage: SpokenLanguage { setup.shown ?? setup.heard }

    var minutesStatus: MinutesGenerator.Status { MinutesGenerator.status(for: minutesLanguage) }

    /// Whether the minutes feature exists on this Mac at all (it is hidden where it cannot work).
    var offersMinutes: Bool { MinutesGenerator.isOffered }

    /// A finished meeting with something in it to write minutes from.
    var canMakeMinutes: Bool {
        !isRunning && canNameLastTranscript && finalizedLines.filter { $0.session == sessionIndex }.count >= 2
    }

    /// The sections of the notes on screen, in order.
    var minutesTemplateSections: [MinutesTemplate.Section] { (minutesScenario ?? scenario).minutes.sections }

    var isWritingMinutes: Bool {
        if case .working = minutesState { true } else { false }
    }

    /// The language a sentence spoken in `spoken` is translated into, nil when nothing is translated.
    func translationLanguage(forSpoken spoken: String) -> String? {
        let active = activeSetup
        guard active.translates, let shown = active.shown else { return nil }
        guard active.bothWays else { return shown.code }
        return spoken == active.heard.code ? shown.code : active.heard.code
    }

    func resetMinutes() {
        minutesTask?.cancel()
        minutesTask = nil
        minutesRun += 1
        minutes = nil
        minutesWrittenIn = nil
        minutesScenario = nil
        minutesFile = nil
        minutesEntries = []
        minutesState = .idle
        panelPage = .conversation
    }

    /// Opens the panel on the minutes view, and starts writing them unless they exist or are being written.
    func showMinutes(start: Bool) {
        setDisplayMode(.panel)
        panelPage = .minutes
        bringOverlayToFront()
        if start, minutesState == .idle || isFailed { makeMinutes() }
    }

    private var isFailed: Bool {
        if case .failed = minutesState { true } else { false }
    }

    func makeMinutes() {
        guard #available(macOS 26.0, *), canMakeMinutes, let url = scriptFile, case .ready = minutesStatus else { return }
        if isWritingMinutes { return }
        let language = minutesLanguage
        let scenario = self.scenario
        minutesRun += 1
        let run = minutesRun
        minutesState = .working(done: 0, total: 1)
        minutesTask = Task { [weak self] in
            // Only the run that owns the state may write to it.
            do {
                let script = ScriptParser.parse(try String(contentsOf: url, encoding: .utf8))
                guard !script.entries.isEmpty else { throw MinutesFailure(message: tr("This transcript has no sentences.", "이 기록에는 문장이 없습니다.")) }
                let result = try await MinutesWriter.generate(entries: script.entries, language: language, scenario: scenario) { done, total in
                    await MainActor.run { if self?.minutesRun == run, !Task.isCancelled { self?.minutesState = .working(done: done, total: total) } }
                }
                try Task.checkCancellation()
                guard self?.minutesRun == run, !Task.isCancelled else { return }
                let file = try TranscriptFiles.writeMinutes(result, entries: script.entries, transcript: url, language: language, template: scenario.minutes)
                self?.minutes = result
                self?.minutesEntries = script.entries
                self?.minutesFile = file
                self?.minutesWrittenIn = language
                self?.minutesScenario = scenario
                self?.minutesState = .ready
            } catch is CancellationError {
                return
            } catch {
                if self?.minutesRun == run, !Task.isCancelled { self?.minutesState = .failed(error.localizedDescription) }
            }
        }
    }

    func cancelMinutes() {
        minutesTask?.cancel()
        minutesTask = nil
        minutesRun += 1
        minutesState = .idle
    }

    /// The minutes as Markdown, for the clipboard.
    var minutesMarkdown: String? {
        guard let minutes, let file = scriptFile else { return nil }
        return MinutesMarkdown.render(minutes, entries: minutesEntries, title: file.deletingPathExtension().lastPathComponent, language: minutesWrittenIn ?? minutesLanguage, template: (minutesScenario ?? scenario).minutes)
    }
}

struct MinutesFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
