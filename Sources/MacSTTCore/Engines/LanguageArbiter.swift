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
        /// How long a final waits for the other recognizer's result for the same speech.
        public var holdSeconds = 0.7
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
    }

    private let locales: [String]
    private let config: Config
    private let plausibility: @Sendable (String, String) -> Double
    private var interims: [String: (event: TranscriptionEvent, score: Double)] = [:]
    private var leader: String?
    private var pending: [Pending] = []

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
        resolve(expiredBefore: now - config.holdSeconds)
    }

    /// End of input: nothing more will arrive, so decide everything that is still waiting.
    public mutating func finish() -> [TranscriptionEvent] {
        resolve(expiredBefore: .infinity)
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
        // The sentence ended, so what was being shown for it is stale for both recognizers.
        interims.removeAll()
        leader = nil
        if let index = pending.firstIndex(where: { $0.locale != locale && Self.overlaps($0.event, event) }) {
            let rival = pending.remove(at: index)
            let winner = rival.score >= score ? rival : Pending(locale: locale, event: event, score: score, arrivedAt: now)
            return winner.score >= config.minimumSoloScore ? [winner.event] : []
        }
        pending.append(Pending(locale: locale, event: event, score: score, arrivedAt: now))
        return flush(now: now)
    }

    private mutating func resolve(expiredBefore deadline: Double) -> [TranscriptionEvent] {
        var out: [TranscriptionEvent] = []
        pending.removeAll { item in
            guard item.arrivedAt <= deadline else { return false }
            if item.score >= config.minimumSoloScore { out.append(item.event) }
            return true
        }
        return out
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
