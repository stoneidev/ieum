import Foundation

/// Diagnostic line on stderr, shared by the CLI and the app.
public func log(_ message: String) {
    FileHandle.standardError.write(Data("ieum: \(message)\n".utf8))
}

public enum TextScript {
    /// Share of letters that are Hangul (0 when there are no letters). Used to size Korean text separately,
    /// because Hangul glyphs look larger and heavier than Latin ones at the same point size.
    public static func hangulRatio(_ text: String) -> Double {
        var letters = 0
        var hangul = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            switch scalar.value {
            case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            default: break
            }
        }
        return letters == 0 ? 0 : Double(hangul) / Double(letters)
    }
}
