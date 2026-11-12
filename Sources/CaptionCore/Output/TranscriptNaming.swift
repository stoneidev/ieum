import Foundation

/// Naming a saved transcript ("Budget meeting") instead of keeping `transcript-2026-11-12_225806-ja-JP`.
/// The exports made from it (`.srt`, `.vtt`, `.md`) keep the same base name, so they follow a rename.
public enum TranscriptNaming {
    public struct Move: Hashable, Sendable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public static let exportExtensions = ["srt", "vtt", "md"]
    public static let maxLength = 80

    /// A name safe to use as a file name, or nil when nothing usable is left. Slashes and colons (not allowed in
    /// names on the Mac) become hyphens; spaces are collapsed; leading dots (hidden files) are dropped.
    public static func sanitize(_ title: String) -> String? {
        var text = title.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "/", ":", "\\": "-"
            default: CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
            }
        }
        .map(String.init).joined()
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix(".") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxLength { text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return text.isEmpty ? nil : text
    }

    /// The renames that give transcript `oldBase` the name `title`: the `.txt` and every export beside it. When the name
    /// is taken by another file, " 2", " 3" … is added. Nil when the name would not change.
    /// - Parameter existing: the file names in the transcripts folder.
    public static func renamePlan(oldBase: String, title: String, existing: [String]) -> (newBase: String, moves: [Move])? {
        guard let wanted = sanitize(title), wanted != oldBase else { return nil }
        let taken = Set(existing.map { $0.lowercased() })
        func isFree(_ base: String) -> Bool {
            (["txt"] + exportExtensions).allSatisfy { !taken.contains("\(base).\($0)".lowercased()) }
        }
        var newBase = wanted
        var number = 2
        // A change of capital letters only ("meeting" to "Meeting") is the same file on the Mac, not a clash.
        while !isFree(newBase), newBase.lowercased() != oldBase.lowercased() {
            newBase = "\(wanted) \(number)"
            number += 1
        }
        if newBase == oldBase { return nil }

        var moves = [Move(from: "\(oldBase).txt", to: "\(newBase).txt")]
        for name in existing.sorted() {
            for ext in exportExtensions {
                let suffix = ".\(ext)"
                guard name.hasSuffix(suffix) else { continue }
                let stem = String(name.dropLast(suffix.count))
                if stem == oldBase {
                    moves.append(Move(from: name, to: "\(newBase)\(suffix)"))
                } else if stem.hasPrefix(oldBase + "-"), Int(stem.dropFirst(oldBase.count + 1)) != nil {
                    moves.append(Move(from: name, to: "\(newBase)\(stem.dropFirst(oldBase.count))\(suffix)"))
                }
            }
        }
        return (newBase, moves)
    }
}
