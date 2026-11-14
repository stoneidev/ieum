import Foundation

/// Finds names and jargon in what was just said that the person has not put in the vocabulary yet, so adding them is one tap
/// instead of remembering and typing them. Only Latin-script words are looked at: they are the ones a recognizer mis-spells.
public enum VocabularySuggester {
    /// Words that start with a capital letter for reasons other than being a name.
    private static let ordinary: Set<String> = [
        "i", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "english", "korean", "japanese", "chinese", "okay",
    ]

    /// - Returns: at most `limit` candidates, the most repeated first. A name or product is suggested when it is spoken at least
    ///   twice (a capitalised word that is not an everyday word), or once when it is written in the mixed case of a product
    ///   (`GraphQL`, `iOS`, `PostgreSQL`). Terms already in `existing` are left out, ignoring case.
    public static func suggestions(
        from sentences: [String],
        existing: [String],
        limit: Int = 5,
        isKnownWord: (String) -> Bool = WordList.isKnownEnglishWord
    ) -> [String] {
        let have = Set(existing.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var spelling: [String: String] = [:]
        var midSentence: Set<String> = []
        var order = 0

        for sentence in sentences {
            let tokens = sentence.split(whereSeparator: \.isWhitespace)
            for (index, raw) in tokens.enumerated() {
                // A line holds several sentences: a word after a full stop opens one, like the first word of the line.
                let opens = index == 0 || ".!?\u{2026}".contains(tokens[index - 1].last ?? " ")
                for word in latinWords(in: String(raw)) {
                    let key = word.lowercased()
                    guard !have.contains(key), !have.contains(singular(key)), !ordinary.contains(key) else { continue }
                    counts[key, default: 0] += 1
                    if firstSeen[key] == nil { firstSeen[key] = order; order += 1 }
                    // Keep the spelling that carries the most capitals: "GraphQL" over "Graphql".
                    if (spelling[key].map { Self.capitals(word) > Self.capitals($0) } ?? true) { spelling[key] = word }
                    if !opens, word.first?.isUppercase == true { midSentence.insert(key) }
                }
            }
        }

        let kept = counts.keys.filter { key in
            guard let word = spelling[key] else { return false }
            if isMixedCase(word) { return true }
            // A plain capitalised word opens every sentence; it is a name only if it shows up inside one and comes back.
            return counts[key, default: 0] >= 2 && midSentence.contains(key) && isCapitalised(word) && !isKnownWord(key)
        }
        return kept
            .sorted { (counts[$0] ?? 0, -(firstSeen[$0] ?? 0)) > (counts[$1] ?? 0, -(firstSeen[$1] ?? 0)) }
            .prefix(limit)
            .compactMap { spelling[$0] }
    }

    /// The Latin words in a token, without punctuation or a possessive. A Korean, Japanese or Chinese particle stuck to a name
    /// ("Kubernetes를") does not hide it: only the run of ASCII letters is taken.
    private static func latinWords(in token: String) -> [String] {
        var words: [String] = []
        var run = ""
        func flush() {
            let word = run.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if word.filter(\.isLetter).count >= 3 { words.append(word) }
            run = ""
        }
        for scalar in token.unicodeScalars {
            if scalar.isASCII, CharacterSet.letters.contains(scalar) || scalar == "-" {
                run.unicodeScalars.append(scalar)
            } else {
                // Anything else ends a word; the tail of "Siobhan's" or "don't" is too short to count.
                flush()
            }
        }
        flush()
        return words
    }

    /// "APIs" -> "api": a plural acronym is the acronym.
    private static func singular(_ key: String) -> String { key.hasSuffix("s") ? String(key.dropLast()) : key }

    private static func capitals(_ word: String) -> Int { word.filter(\.isUppercase).count }

    private static func isCapitalised(_ word: String) -> Bool {
        word.first?.isUppercase == true && word.dropFirst().allSatisfy { $0.isLowercase || $0 == "-" }
    }

    /// `GraphQL`, `iOS`, `iPhone`, `PostgreSQL`: a capital inside the word, but not a shouted word, a plural acronym (`APIs`) or a
    /// hyphenated phrase.
    private static func isMixedCase(_ word: String) -> Bool {
        guard !word.contains("-") else { return false }
        let letters = word.filter(\.isLetter)
        let upper = letters.filter(\.isUppercase).count
        let lower = letters.count - upper
        if lower == 1, letters.last == "s", upper >= 2 { return false }
        return letters.first?.isUppercase == true ? upper >= 2 && upper < letters.count : upper >= 1
    }
}
