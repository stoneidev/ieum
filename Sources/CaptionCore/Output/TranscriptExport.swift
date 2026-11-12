import Foundation

/// One sentence of a saved transcript: when it was spoken (seconds after the session started), its language tag in
/// conversation transcripts, the sentence and its translation.
public struct ScriptEntry: Equatable, Sendable {
    public var offset: TimeInterval
    public var language: String?
    public var text: String
    public var translation: String?

    public init(offset: TimeInterval, language: String? = nil, text: String, translation: String? = nil) {
        self.offset = offset
        self.language = language
        self.text = text
        self.translation = translation
    }
}

/// Reads the text files `ScriptRecorder` writes: a `# Transcript … started yyyy-MM-dd HH:mm:ss` header, then one
/// `[HH:mm:ss] sentence` line per sentence and `[HH:mm:ss] → translation` lines for translations.
public enum ScriptParser {
    public struct Script: Equatable, Sendable {
        public var startedAt: Date?
        public var entries: [ScriptEntry]
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> Script {
        var startedAt: Date?
        var startSeconds: Double?
        var entries: [ScriptEntry] = []
        var times: [String] = []   // the time string of each entry, to match a translation to its sentence
        let line = try! NSRegularExpression(pattern: #"^\[(\d{2}):(\d{2}):(\d{2})\] (?:\[([A-Za-z]{2})\] )?(→ )?(.*)$"#)

        for raw in text.split(whereSeparator: \.isNewline) {
            let row = String(raw)
            if row.hasPrefix("# Transcript"), let range = row.range(of: " started ") {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                startedAt = formatter.date(from: String(row[range.upperBound...]).trimmingCharacters(in: .whitespaces))
                if let startedAt {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = timeZone
                    let c = calendar.dateComponents([.hour, .minute, .second], from: startedAt)
                    startSeconds = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
                }
                continue
            }
            let ns = row as NSString
            guard let match = line.firstMatch(in: row, range: NSRange(location: 0, length: ns.length)) else { continue }
            func group(_ i: Int) -> String? { match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i)) }
            let h = Double(group(1) ?? "0") ?? 0, m = Double(group(2) ?? "0") ?? 0, s = Double(group(3) ?? "0") ?? 0
            let clock = h * 3600 + m * 60 + s
            let stamp = "\(group(1) ?? ""):\(group(2) ?? ""):\(group(3) ?? "")"
            let content = (group(6) ?? "").trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            if group(5) != nil {
                // A translation belongs to the latest sentence written at the same time that has none yet.
                if let index = times.lastIndex(of: stamp), entries[index].translation == nil {
                    entries[index].translation = content
                } else if !entries.isEmpty, entries[entries.count - 1].translation == nil {
                    entries[entries.count - 1].translation = content
                }
                continue
            }
            var offset = clock - (startSeconds ?? clock)
            if offset < 0 { offset += 86_400 }   // the meeting went past midnight
            entries.append(ScriptEntry(offset: offset, language: group(4)?.lowercased(), text: content))
            times.append(stamp)
        }
        return Script(startedAt: startedAt, entries: entries)
    }
}

/// Turns a transcript into subtitle files (SRT, WebVTT) or Markdown notes.
public enum TranscriptExport {
    public enum Format: String, CaseIterable, Sendable {
        case srt, vtt, markdown

        public var fileExtension: String { self == .markdown ? "md" : rawValue }
    }

    /// What goes into each subtitle cue.
    public enum Content: Sendable {
        case both, original, translation
    }

    public static func render(_ script: ScriptParser.Script, format: Format, content: Content = .both, title: String = "Transcript", timeZone: TimeZone = .current) -> String {
        switch format {
        case .srt: return cues(script.entries, content: content, vtt: false)
        case .vtt: return "WEBVTT\n\n" + cues(script.entries, content: content, vtt: true)
        case .markdown: return markdown(script, content: content, title: title, timeZone: timeZone)
        }
    }

    // MARK: Subtitles

    private static func cues(_ entries: [ScriptEntry], content: Content, vtt: Bool) -> String {
        var out = ""
        var number = 1
        for (index, entry) in entries.enumerated() {
            let lines = cueLines(entry, content: content)
            guard !lines.isEmpty else { continue }
            let next = index + 1 < entries.count ? entries[index + 1].offset : nil
            let end = cueEnd(start: entry.offset, text: lines.joined(), next: next)
            if !vtt { out += "\(number)\n" }
            out += "\(timecode(entry.offset, comma: !vtt)) --> \(timecode(end, comma: !vtt))\n\(lines.joined(separator: "\n"))\n\n"
            number += 1
        }
        return out
    }

    private static func cueLines(_ entry: ScriptEntry, content: Content) -> [String] {
        switch content {
        case .original: [entry.text]
        case .translation: [entry.translation ?? entry.text]
        case .both: [entry.text] + (entry.translation.map { [$0] } ?? [])
        }
    }

    /// Shown long enough to read, but never into the next cue.
    static func cueEnd(start: TimeInterval, text: String, next: TimeInterval?) -> TimeInterval {
        let wide = TextScript.cjkRatio(text) > 0.5
        let readable = min(8, max(1.5, Double(text.count) * (wide ? 0.18 : 0.07) + 1.2))
        var end = start + readable
        if let next, next > start { end = min(end, max(next - 0.1, start + 0.8)) }
        return end
    }

    static func timecode(_ seconds: TimeInterval, comma: Bool) -> String {
        let total = Int((max(0, seconds) * 1000).rounded())
        let ms = total % 1000, s = (total / 1000) % 60, m = (total / 60_000) % 60, h = total / 3_600_000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, comma ? "," : ".", ms)
    }

    // MARK: Markdown

    private static func markdown(_ script: ScriptParser.Script, content: Content, title: String, timeZone: TimeZone) -> String {
        var out = "# \(title)\n\n"
        if let startedAt = script.startedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            out += "Started \(formatter.string(from: startedAt))\n\n"
        }
        for entry in script.entries {
            let lines = cueLines(entry, content: content)
            guard let first = lines.first else { continue }
            let clock = timecode(entry.offset, comma: false).prefix(8)
            let tag = entry.language.map { " `\($0.uppercased())`" } ?? ""
            out += "**\(clock)**\(tag) \(first)"
            for extra in lines.dropFirst() { out += "  \n> \(extra)" }
            out += "\n\n"
        }
        return out
    }
}
