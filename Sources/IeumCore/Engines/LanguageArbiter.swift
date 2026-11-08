import Foundation
import NaturalLanguage

/// Decides, utterance by utterance, which of several recognizers heard the speech in the right language.
///
/// Conversation mode runs one recognizer per language on the same audio. The one in the wrong language
/// either returns nothing or returns confident-looking nonsense, so a result is scored by the recognizer's
/// own confidence times how much the text looks like the recognizer's language.
///
/// The arbiter is a pure state machine driven by the caller's clock (`now`, in seconds), so it can be tested
/// without audio or timers.
public struct LanguageArbiter {
    public struct Config: Sendable {
        /// How long a confident final waits for the other recognizer's result for the same speech.
        public var holdSeconds = 0.7
        /// A final scoring below `weakScore` waits this long: its rival may still arrive and is probably better.
        public var weakHoldSeconds = 1.8
        public var weakScore = 0.75
        /// A final at least this sure is shown at once when the other recognizer offered nothing credible meanwhile
        /// (its best interim scored below `rivalInterimCeiling`). Waiting would only add delay.
        public var confidentScore = 0.9
        public var rivalInterimCeiling = 0.3
        /// A final nobody competes with is still dropped below this score (wrong-language noise).
        public var minimumSoloScore = 0.35
        /// An interim of another language takes over the display when its score is this much higher.
        public var switchRatio = 1.25
        /// Used when an engine reports no confidence.
        public var assumedConfidence = 0.6
        public init() {}
    }

    private struct Pending {
        let locale: String
        let event: TranscriptionEvent
        let score: Double
        let arrivedAt: Double
        /// Decided already (the rival arrived or nothing credible competes): only waits for earlier sentences.
        var ready = false

        /// Sentences are shown in the order they were spoken.
        var order: Double { event.audioStart ?? arrivedAt }
    }

    private let locales: [String]
    private let config: Config
    private let plausibility: @Sendable (String, String) -> Double
    private var interims: [String: (event: TranscriptionEvent, score: Double)] = [:]
    private var leader: String?
    private var pending: [Pending] = []
    /// Audio ranges of finals already shown, to recognize the same speech arriving a second time from the other recognizer.
    private var shown: [(start: Double, end: Double, locale: String, score: Double)] = []

    public init(
        locales: [String],
        config: Config = Config(),
        plausibility: @escaping @Sendable (String, String) -> Double = LanguageArbiter.textPlausibility
    ) {
        self.locales = locales
        self.config = config
        self.plausibility = plausibility
    }

    // MARK: Driving the arbiter

    /// Feed one recognizer event. Returns the events that should be shown now.
    public mutating func ingest(_ event: TranscriptionEvent, from locale: String, now: Double) -> [TranscriptionEvent] {
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return event.isFinal ? flush(now: now) : [] }
        let score = score(event, locale: locale)
        return event.isFinal ? ingestFinal(event, locale: locale, score: score, now: now) : ingestInterim(event, locale: locale, score: score)
    }

    /// Emits finals whose waiting time ran out.
    public mutating func flush(now: Double) -> [TranscriptionEvent] {
        let config = self.config
        return release { item in
            item.ready || now - item.arrivedAt >= (item.score < config.weakScore ? config.weakHoldSeconds : config.holdSeconds)
        }
    }

    /// End of input: nothing more will arrive, so decide everything that is still waiting.
    public mutating func finish() -> [TranscriptionEvent] {
        release { _ in true }
    }

    // MARK: Interim results

    private mutating func ingestInterim(_ event: TranscriptionEvent, locale: String, score: Double) -> [TranscriptionEvent] {
        interims[locale] = (event, score)
        let best = interims.max { $0.value.score < $1.value.score }
        guard let best else { return [] }
        if let current = leader, let currentScore = interims[current]?.score, currentScore > 0 {
            if best.key != current, best.value.score > currentScore * config.switchRatio {
                leader = best.key
            }
        } else {
            leader = best.key
        }
        // Only the leading recognizer is shown; the other one's chatter stays hidden.
        return leader == locale ? [event] : []
    }

    // MARK: Final results

    private mutating func ingestFinal(_ event: TranscriptionEvent, locale: String, score: Double, now: Double) -> [TranscriptionEvent] {
        // What the other recognizer offered while this sentence was spoken, before that is cleared as stale.
        let rivalInterim = interims.filter { $0.key != locale }.map(\.value.score).max() ?? 0
        interims.removeAll()
        leader = nil
        if let index = pending.firstIndex(where: { $0.locale != locale && Self.overlaps($0.event, event) }) {
            let rival = pending.remove(at: index)
            var winner = rival.score >= score ? rival : Pending(locale: locale, event: event, score: score, arrivedAt: now)
            winner.ready = true
            pending.append(winner)
            return flush(now: now)
        }
        var item = Pending(locale: locale, event: event, score: score, arrivedAt: now)
        item.ready = score >= config.confidentScore && rivalInterim < config.rivalInterimCeiling
        pending.append(item)
        return flush(now: now)
    }

    /// Shows what is due, strictly in the order it was spoken: a due sentence never overtakes an earlier one that is
    /// still waiting for its rival.
    private mutating func release(where isDue: (Pending) -> Bool) -> [TranscriptionEvent] {
        var out: [TranscriptionEvent] = []
        var waiting: [Pending] = []
        var blocked = false
        for item in pending.sorted(by: { $0.order < $1.order }) {
            if !blocked, isDue(item) {
                if item.score >= config.minimumSoloScore { out.append(contentsOf: show(item)) }
            } else {
                blocked = true
                waiting.append(item)
            }
        }
        pending = waiting
        return out
    }

    /// Emits a final unless the other recognizer's version of the same speech was already shown.
    /// A later rival that scores *higher* than what was shown is not a duplicate but the real sentence (the earlier
    /// one was the wrong-language recognizer's noise), so it is shown too.
    private mutating func show(_ item: Pending) -> [TranscriptionEvent] {
        if let start = item.event.audioStart, let end = item.event.audioEnd {
            let own = max(end - start, 0.01)
            let duplicate = shown.contains { other in
                other.locale != item.locale && item.score <= other.score
                    && min(end, other.end) - max(start, other.start) > 0.5 * min(own, other.end - other.start)
            }
            if duplicate { return [] }
            shown.append((start, end, item.locale, item.score))
            if shown.count > 20 { shown.removeFirst(shown.count - 20) }
        }
        return [item.event]
    }

    // MARK: Scoring

    private func score(_ event: TranscriptionEvent, locale: String) -> Double {
        (event.confidence ?? config.assumedConfidence) * plausibility(event.text, locale)
    }

    /// Two results are about the same speech when their audio ranges overlap (or when ranges are unknown).
    private static func overlaps(_ a: TranscriptionEvent, _ b: TranscriptionEvent) -> Bool {
        guard let aStart = a.audioStart, let aEnd = a.audioEnd, let bStart = b.audioStart, let bEnd = b.audioEnd else { return true }
        return max(aStart, bStart) < min(aEnd, bEnd) - 0.05
    }

    /// How much `text` looks like it is written in the language of `locale` (0.05...1).
    public static func textPlausibility(text: String, locale: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = NLLanguage(rawValue: String(locale.prefix(2)))
        return max(recognizer.languageHypotheses(withMaximum: 6)[language] ?? 0, 0.05)
    }
}
