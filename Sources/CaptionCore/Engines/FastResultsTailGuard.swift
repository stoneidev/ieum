import Foundation

/// Decides when a fast-results final should wait for a slower, complete final.
///
/// SpeechTranscriber with `.fastResults` can stop growing interim text and then finalize while the person is still
/// speaking, dropping the tail (measured on the Korean codeswitch passage in `docs/TRANSCRIPTION-RESEARCH.md`). A
/// second analyzer without fast results keeps the tail. This guard only answers "hold this fast final?" and
/// "is the slow final the better complete sentence?".
///
/// The measured codeswitch truncation reports `audioEnd` at the end of the audio even when the text stopped early,
/// so `shouldHoldFinal(audioEnd:…)` alone never fires. `shouldHoldForStalledText` catches that: interim letter count
/// stopped growing while speech continued, and the final did not add the missing tail.
public enum FastResultsTailGuard {
    /// Speech heard this far past a final's `audioEnd` means the final likely cut the utterance short.
    public static let speechPastFinal: TimeInterval = 0.35

    /// Speech heard this far past the last interim letter-count growth means the recognizer stalled.
    /// Matches the codeswitch dump: interim stopped ~12.5 s, speech went on to ~15 s.
    public static let interimStall: TimeInterval = 0.5

    /// Extra letters a final may add (punctuation, a short particle) without counting as a completed tail.
    public static let finalLetterSlack = 4

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

    /// Hold when interim text stopped growing while this utterance's speech continued, and the final did not
    /// grow past that stall (`<= lastInterimLetters + finalLetterSlack` still holds — a few extra letters are
    /// punctuation or a particle, not proof the tail arrived).
    ///
    /// On `codeswitch-ko` the truncated final's `audioEnd` is the end of the file, so the audio-range hold never
    /// fires; the interim letter count still stops early while the final's own range keeps extending
    /// (docs/BENCHMARKS.md). Prefer `audioEnd` over the session-wide speech watermark so a later speaker cannot
    /// make a finished sentence look truncated.
    public static func shouldHoldForStalledText(
        finalText: String,
        audioEnd: Double?,
        lastInterimLetters: Int,
        lastInterimGrowthAt: Double,
        lastSpeechAt: Double,
        interimStall: TimeInterval = interimStall,
        finalLetterSlack: Int = finalLetterSlack
    ) -> Bool {
        guard lastInterimLetters > 0, lastInterimGrowthAt.isFinite else { return false }
        let speechHint = audioEnd ?? lastSpeechAt
        guard speechHint.isFinite, speechHint > lastInterimGrowthAt + interimStall else { return false }
        return letterCount(finalText) <= lastInterimLetters + finalLetterSlack
    }

    /// Either the audio-range hold or the interim-stall hold.
    public static func shouldHold(
        finalText: String,
        audioEnd: Double?,
        lastSpeechAt: Double,
        lastInterimLetters: Int,
        lastInterimGrowthAt: Double
    ) -> Bool {
        shouldHoldFinal(audioEnd: audioEnd, lastSpeechAt: lastSpeechAt)
            || shouldHoldForStalledText(
                finalText: finalText,
                audioEnd: audioEnd,
                lastInterimLetters: lastInterimLetters,
                lastInterimGrowthAt: lastInterimGrowthAt,
                lastSpeechAt: lastSpeechAt
            )
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
