import Foundation

/// Removes the filler the recognizer writes for stretches it cannot decode, such as laughter, applause or music
/// (`,,`, `-...`, `NVI.........`), so it is neither shown nor translated nor saved.
public enum TranscriptCleaner {
    /// Punctuation the recognizer uses as a placeholder: a run of at least two of these.
    private static let filler = try! NSRegularExpression(pattern: "[,.…\\-–—]{2,}")
    private static let leading = try! NSRegularExpression(pattern: "^[\\s,.…\\-–—]+")
    private static let repeatedEllipsis = try! NSRegularExpression(pattern: "…(?:\\s*…)+")

    public static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.contains(where: { ",.…-–—".contains($0) }) else { return result }

        // Filler before the first word is dropped; there is nothing to say it belonged to.
        result = leading.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

        // Filler between words becomes one ellipsis (or a single comma when it is only commas).
        let matches = filler.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = result[range]
            let onlyCommas = run.allSatisfy { $0 == "," }
            result.replaceSubrange(range, with: onlyCommas ? "," : "…")
        }
        result = repeatedEllipsis.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "…")
        // "word …" -> "word…"
        result = result.replacingOccurrences(of: " …", with: "…")

        // Nothing but filler is left: there is no sentence to show.
        guard result.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return "" }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
