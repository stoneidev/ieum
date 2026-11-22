import Foundation

/// The pure parts of the reply helper: someone who must answer in the other side's language types (or quietly says) what
/// they mean in their own, and gets a sentence to read out. Translation and the language model are in the app.
public enum ReplyHelper {
    /// A reply is a sentence or two; more than this is not something to read out in a meeting.
    public static let maxCharacters = 600

    /// What was typed or said, ready to translate: one line, spaces collapsed, cut at `maxCharacters`. Nil when there is nothing to translate.
    public static func prepare(_ raw: String) -> String? {
        var text = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) : text
    }

    /// Whether a rewrite from the language model may replace the plain translation. It is a rewrite, not an answer:
    /// it must stay in the target language and must not grow into an essay or shrink to nothing.
    public static func acceptsPolished(literal: String, candidate: String, target: SpokenLanguage) -> Bool {
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= max(literal.count * 3, 60), text.count * 10 >= literal.count * 7 else { return false }
        guard keepsFacts(literal: literal, candidate: text) else { return false }
        let wide = TextScript.cjkRatio(text)
        switch target {
        case .english: return wide < 0.1
        case .korean: return TextScript.hangulRatio(text) > 0.5
        case .japanese, .chinese: return wide > 0.5
        }
    }

    private static let openers: Set<String> = [
        "the", "a", "an", "i", "we", "you", "he", "she", "it", "they", "this", "that", "these", "those", "there", "here",
        "can", "could", "would", "should", "will", "shall", "may", "might", "must", "do", "does", "did", "is", "are", "was", "were",
        "have", "has", "had", "please", "yes", "no", "sorry", "thanks", "thank", "sure", "well", "so", "but", "and", "or", "if",
        "when", "what", "why", "how", "who", "where", "which", "let", "let's", "maybe", "actually", "also", "just", "my", "our",
        "your", "his", "her", "their", "its", "for", "to", "in", "on", "at", "after", "before", "by", "with", "unfortunately",
        "honestly", "basically", "currently", "next", "last", "today", "tomorrow", "yesterday", "once", "since", "as", "not",
        "okay", "ok", "great", "right", "sounds", "looks", "agreed", "understood", "hello", "hi", "good", "perfect", "certainly",
        "absolutely", "of", "thank", "no", "yeah", "alright", "totally", "definitely", "probably", "hopefully", "still", "then",
    ]

    /// A smoother sentence must still say the same thing: a question stays a question, every number is still there, and so
    /// is every name, weekday and month (capital letters inside a sentence in a Latin script).
    static func keepsFacts(literal: String, candidate: String) -> Bool {
        let askedBefore = literal.contains("?") || literal.contains("？")
        let asksNow = candidate.contains("?") || candidate.contains("？")
        guard askedBefore == asksNow else { return false }
        func numbers(_ text: String) -> Set<String> {
            Set(text.split(whereSeparator: { !$0.isNumber }).map(String.init))
        }
        guard numbers(literal).isSubset(of: numbers(candidate)) else { return false }
        func names(_ text: String) -> Set<String> {
            // Words with their place in the sentence: the first word of each sentence is capitalised anyway.
            var found = Set<String>()
            var word = ""
            var atStart = true
            func finish() {
                defer { word = "" }
                guard let first = word.first else { return }
                // "It's", "We'll", "Don't": the word before the apostrophe decides.
                let isOpener = openers.contains(String(word.lowercased().split(separator: "'").first ?? ""))
                if first.isUppercase, word != "I", !word.hasPrefix("I'"), !(atStart && isOpener) { found.insert(word) }
                atStart = false
            }
            for character in text {
                if character.isLetter || character == "'" || character == "\u{2019}" {
                    word.append(character == "\u{2019}" ? "'" : character)
                } else {
                    finish()
                    if ".!?？。".contains(character) { atStart = true }
                }
            }
            finish()
            return found
        }
        return names(literal).isSubset(of: names(candidate))
    }

    /// The first thing said: waits for a finished sentence, or, if the stream ends first, takes what was heard so far.
    public static func firstUtterance(from events: AsyncThrowingStream<TranscriptionEvent, Error>) async throws -> String? {
        var heard = ""
        for try await event in events {
            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if event.isFinal, !text.isEmpty { return text }
            if !text.isEmpty { heard = text }
        }
        return heard.isEmpty ? nil : heard
    }
}
