import Foundation

/// Diagnostic line on stderr, shared by the CLI and the app.
public func log(_ message: String) {
    FileHandle.standardError.write(Data("caption: \(message)\n".utf8))
}

public enum TextScript {
    /// Share of letters that are Hangul (0 when there are no letters). Used to size Korean text separately,
    /// because Hangul glyphs look larger and heavier than Latin ones at the same point size.
    public static func hangulRatio(_ text: String) -> Double {
        ratio(of: text) { (0xAC00...0xD7A3).contains($0) || (0x1100...0x11FF).contains($0) || (0x3130...0x318F).contains($0) }
    }

    /// Share of letters that are Hangul, kana or Han characters. These glyphs fill their whole square, so they are sized
    /// separately from Latin text (0 when there are no letters).
    public static func cjkRatio(_ text: String) -> Double {
        ratio(of: text) { hangulRatio(String(UnicodeScalar($0)!)) > 0 || isUnspaced($0) }
    }

    /// Kana and Han characters: written without spaces between words, so pieces of one sentence are joined directly.
    public static func isUnspaced(_ value: UInt32) -> Bool {
        (0x3040...0x30FF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0x3000...0x303F).contains(value) || (0xFF00...0xFFEF).contains(value)
    }

    /// The separator to put between two pieces of one sentence: nothing next to Japanese or Chinese text, a space otherwise.
    public static func joiner(between left: String, and right: String) -> String {
        guard let end = left.unicodeScalars.last, let start = right.unicodeScalars.first else { return "" }
        return isUnspaced(end.value) || isUnspaced(start.value) ? "" : " "
    }

    /// The pieces of one sentence run together, each pair separated the way `joiner` says. Empty pieces are skipped.
    public static func join(_ pieces: [String]) -> String {
        pieces.filter { !$0.isEmpty }.reduce("") { $0.isEmpty ? $1 : $0 + joiner(between: $0, and: $1) + $1 }
    }

    private static func ratio(of text: String, matching: (UInt32) -> Bool) -> Double {
        var letters = 0
        var matches = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if matching(scalar.value) { matches += 1 }
        }
        return letters == 0 ? 0 : Double(matches) / Double(letters)
    }
}
