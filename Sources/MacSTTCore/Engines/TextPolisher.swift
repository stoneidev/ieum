import Foundation

/// Guards LLM output: only light edits (spacing, punctuation, tiny fixes) may replace the recognizer's text.
/// Translations, rewrites, reorderings and deletions fall below the similarity threshold and are rejected.
enum PolishGuard {
    static let minimumSimilarity = 0.9
    static let maximumLength = 1000

    static func accepts(original: String, candidate: String) -> Bool {
        let a = normalize(original)
        let b = normalize(candidate)
        guard !a.isEmpty, !b.isEmpty, a.count <= maximumLength, b.count <= maximumLength else { return false }
        return similarity(a, b) >= minimumSimilarity
    }

    /// Letters and digits only, case-folded: spacing and punctuation changes are free.
    static func normalize(_ text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 1 - editDistance / maxLength.
    static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        if a == b { return 1 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}

/// Optional post-processor for finalized sentences. Interim results are never touched.
public struct FinalTextPolisher: Sendable {
    let polish: @Sendable (String) async -> String?

    public func apply(to event: TranscriptionEvent) async -> TranscriptionEvent {
        guard event.isFinal else { return event }
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let candidate = await polish(text), PolishGuard.accepts(original: text, candidate: candidate) else {
            return event
        }
        return TranscriptionEvent(
            text: candidate.trimmingCharacters(in: .whitespacesAndNewlines),
            isFinal: true, locale: event.locale, timestamp: event.timestamp,
            audioStart: event.audioStart, audioEnd: event.audioEnd
        )
    }

    /// Returns nil (with a stderr note) when the on-device model cannot be used.
    public static func onDevice() async -> FinalTextPolisher? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return await OnDeviceLanguageModelPolisher.make() }
        #endif
        log("--polish needs macOS 26 with Apple Intelligence; continuing without it")
        return nil
    }
}

#if compiler(>=6.2)
import FoundationModels

/// Uses only `SystemLanguageModel` (on-device). The cloud `PrivateCloudComputeLanguageModel` is never referenced.
@available(macOS 26.0, *)
enum OnDeviceLanguageModelPolisher {
    static let instructions = """
    You fix speech-recognition errors: spacing, punctuation, and clearly misheard words. \
    Keep the speaker's language, wording and meaning. Never translate, answer, summarize, reorder, add or remove content. \
    Output only the corrected sentence.
    """

    static func make() async -> FinalTextPolisher? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            log("--polish: the on-device language model is not available (\(model.availability)); continuing without it")
            return nil
        }
        let polisher = FinalTextPolisher { text in
            await run(text, timeout: .seconds(3))
        }
        // The first call loads the model (several seconds). Finish that before speech recognition starts:
        // loading concurrently competes for the same hardware and delays the first words.
        log("--polish: loading the on-device language model...")
        _ = await run("준비", timeout: .seconds(30))
        return polisher
    }

    private static func run(_ text: String, timeout: Duration) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                return try? await session.respond(to: text, options: GenerationOptions(temperature: 0)).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
#endif
