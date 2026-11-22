import Foundation

/// Decides when a fast-results final should wait for a slower, complete final.
///
/// SpeechTranscriber with `.fastResults` can stop growing interim text and then finalize while the person is still
/// speaking, dropping the tail (measured on the Korean codeswitch passage in `docs/TRANSCRIPTION-RESEARCH.md`). A
/// second analyzer without fast results keeps the tail. This guard only answers "hold this fast final?" and
/// "is the slow final the better complete sentence?".
public enum FastResultsTailGuard {
    /// Speech heard this far past a final's `audioEnd` means the final likely cut the utterance short.
    public static let speechPastFinal: TimeInterval = 0.35

    /// Locales where the silent tail drop was measured (and where a second analyzer is worth the cost).
    public static func applies(to localeID: String) -> Bool {
        localeID.lowercased().hasPrefix("ko")
    }

    /// Hold a fast final when speech continued after its audio range ended.
    public static func shouldHoldFinal(
        audioEnd: Double?,
        lastSpeechAt: Double,
        speechPastFinal: TimeInterval = speechPastFinal
    ) -> Bool {
        guard let end = audioEnd, end.isFinite, lastSpeechAt.isFinite else { return false }
        return lastSpeechAt > end + speechPastFinal
    }

    /// Prefer the slow final when it covers the same span with clearly more letters.
    public static func prefersSlow(
        fastText: String,
        slowText: String,
        fastRange: (start: Double, end: Double)?,
        slowRange: (start: Double, end: Double)?
    ) -> Bool {
        let slowLetters = letterCount(slowText)
        let fastLetters = letterCount(fastText)
        guard slowLetters > fastLetters else { return false }
        guard let fastRange, let slowRange else {
            // Without ranges, a longer slow final after a held fast one is still the recovery we want.
            return true
        }
        return rangesOverlap(fastRange, slowRange)
    }

    public static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (CharacterSet.alphanumerics.contains($1) ? 1 : 0) }
    }

    public static func rangesOverlap(_ a: (start: Double, end: Double), _ b: (start: Double, end: Double)) -> Bool {
        a.start < b.end && b.start < a.end
    }

    public static func range(of event: TranscriptionEvent) -> (start: Double, end: Double)? {
        guard let start = event.audioStart, let end = event.audioEnd, start.isFinite, end.isFinite, end >= start else {
            return nil
        }
        return (start, end)
    }
}
