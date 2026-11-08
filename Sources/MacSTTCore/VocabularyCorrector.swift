import Foundation

/// Repairs recognizer output with the user's meeting vocabulary.
///
/// Speech models split or mis-spell names and jargon ("R. Q. Bernates", "Jera", "figma"). Telling the
/// recognizer about the words does not help every engine (measured: no effect on SpeechTranscriber), so the
/// text is corrected afterwards: a run of one to a few words that sounds like a term is replaced by the term.
/// It works the same for every engine and runs before translation, so the translation gets the right word.
public struct VocabularyCorrector: Sendable {
    private struct Term: Sendable {
        let text: String
        let key: [Character]
        let tokenCount: Int
    }

    private let terms: [Term]
    private let maxWindow: Int

    public init(terms: [String]) {
        var seen = Set<String>()
        self.terms = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .map { Term(text: $0, key: Self.key($0), tokenCount: max(1, $0.split(separator: " ").count)) }
            .filter { $0.key.count >= 2 }
        maxWindow = min(5, (self.terms.map(\.tokenCount).max() ?? 1) + 3)
    }

    public var isEmpty: Bool { terms.isEmpty }

    public func correct(_ text: String) -> String {
        guard !terms.isEmpty, !text.isEmpty else { return text }
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(Token.init)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            if let (replacement, consumed) = bestMatch(in: tokens, at: index) {
                output.append(replacement)
                index += consumed
            } else {
                output.append(tokens[index].raw)
                index += 1
            }
        }
        return output.joined(separator: " ")
    }

    // MARK: Matching

    private struct Token {
        let raw: String
        let leading: String
        let core: String
        let trailing: String

        init(_ raw: Substring) {
            self.raw = String(raw)
            let scalars = Array(raw.unicodeScalars)
            var start = 0
            var end = scalars.count
            while start < end, !Self.isWordScalar(scalars[start]) { start += 1 }
            while end > start, !Self.isWordScalar(scalars[end - 1]) { end -= 1 }
            func join(_ range: Range<Int>) -> String {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[range])
                return String(view)
            }
            leading = join(0..<start)
            core = join(start..<end)
            trailing = join(end..<scalars.count)
        }

        static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    private func bestMatch(in tokens: [Token], at start: Int) -> (String, Int)? {
        var best: (score: Double, replacement: String, consumed: Int)?
        for length in 1...min(maxWindow, tokens.count - start) {
            let window = tokens[start..<(start + length)]
            let windowKey = Self.key(window.map(\.core).joined())
            guard windowKey.count >= 2 else { continue }
            for term in terms {
                // Windows far longer or shorter than the term cannot sound like it.
                let ratio = Double(windowKey.count) / Double(term.key.count)
                guard ratio > 0.6, ratio < 1.5 else { continue }
                guard let score = Self.score(windowKey, term.key) else { continue }
                // A fuzzy match must need every word of its window. When dropping the first or last word scores clearly
                // better ("the Kubernetes", "and Terraform"), that word is not part of the term.
                if score < 1, length > 1 {
                    let withoutFirst = Self.key(window.dropFirst().map(\.core).joined())
                    let withoutLast = Self.key(window.dropLast().map(\.core).joined())
                    let shorter = max(Self.score(withoutFirst, term.key) ?? 0, Self.score(withoutLast, term.key) ?? 0)
                    if shorter > score + 0.05 { continue }
                }
                let replacement = window.first!.leading + term.text + window.last!.trailing
                // Prefer the better score; on a tie prefer the longer window (it fixes split words).
                if best == nil || score > best!.score + 1e-9 || (abs(score - best!.score) < 1e-9 && length > best!.consumed) {
                    best = (score, replacement, length)
                }
            }
        }
        guard let best else { return nil }
        // Leave the text alone when nothing changes.
        let original = tokens[start..<(start + best.consumed)].map(\.raw).joined(separator: " ")
        return original == best.replacement ? nil : (best.replacement, best.consumed)
    }

    /// A similarity in 0...1 when `window` should be treated as `term`, otherwise nil.
    private static func score(_ window: [Character], _ term: [Character]) -> Double? {
        if window == term { return 1 }
        // Short terms (OKR, AWS) must match exactly apart from case and spacing: fuzzy matching them would
        // rewrite ordinary words.
        guard term.count >= 4 else { return nil }
        // A word that merely continues the term is something else (Korean particles: 쿠버네티스를; plurals).
        if window.starts(with: term) || term.starts(with: window) { return nil }
        let distance = TextMetrics.editDistance(window, term)
        let similarity = 1 - Double(distance) / Double(max(window.count, term.count))
        let threshold = term.count >= 7 ? 0.7 : 0.75
        return similarity >= threshold ? similarity : nil
    }

    private static func key(_ text: String) -> [Character] {
        text.lowercased().unicodeScalars.filter(Token.isWordScalar).map(Character.init)
    }
}

extension TranscriptionEvent {
    func replacingText(_ text: String) -> TranscriptionEvent {
        TranscriptionEvent(
            text: text, isFinal: isFinal, locale: locale, timestamp: timestamp,
            audioStart: audioStart, audioEnd: audioEnd, confidence: confidence
        )
    }
}

extension VocabularyCorrector {
    /// Applies the correction to every event of a stream (partials and finals alike).
    public func apply(to stream: AsyncThrowingStream<TranscriptionEvent, Error>) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        guard !isEmpty else { return stream }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream { continuation.yield(event.replacingText(correct(event.text))) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
