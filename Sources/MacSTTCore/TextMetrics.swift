import Foundation

/// Recognition-quality metrics for the benchmark.
public enum TextMetrics {
    /// Lowercased, punctuation removed, whitespace collapsed.
    public static func normalize(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Word error rate: edit distance over words divided by the number of reference words.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = normalize(reference).split(separator: " ").map(String.init)
        let hyp = normalize(hypothesis).split(separator: " ").map(String.init)
        return errorRate(ref, hyp)
    }

    /// Character error rate ignoring spaces. This is the fairer measure for Korean, where spacing varies.
    public static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = Array(normalize(reference).filter { $0 != " " })
        let hyp = Array(normalize(hypothesis).filter { $0 != " " })
        return errorRate(ref, hyp)
    }

    private static func errorRate<T: Equatable>(_ ref: [T], _ hyp: [T]) -> Double {
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
