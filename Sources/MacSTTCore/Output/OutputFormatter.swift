import Foundation

public enum OutputFormat: String, CaseIterable, Sendable {
    case text
    case jsonl
}

/// Pure renderer: turns events into the exact bytes to write. Keeps the "live line" state.
public struct OutputFormatter {
    static let clearLine = "\r\u{001B}[K"

    let format: OutputFormat
    /// Text mode only: false when stdout is not a terminal, so no partials / escape codes are emitted.
    let interactive: Bool
    /// Terminal width used to keep the live line on a single row.
    public var columns: Int?
    private let timeZone: TimeZone
    private var pending: TranscriptionEvent?
    private var liveLineShown = false

    public init(format: OutputFormat, interactive: Bool = true, columns: Int? = nil, timeZone: TimeZone = .current) {
        self.format = format
        self.interactive = interactive
        self.columns = columns
        self.timeZone = timeZone
    }

    public mutating func render(_ event: TranscriptionEvent) -> String {
        let text = RepetitionGuard.collapse(event.text.trimmingCharacters(in: .whitespacesAndNewlines))
        if event.isFinal { pending = nil } else { pending = text.isEmpty ? nil : event }

        switch format {
        case .jsonl:
            return text.isEmpty && event.isFinal ? "" : jsonLine(event, text: text)
        case .text:
            return renderText(event, text: text)
        }
    }

    /// Flushes whatever is still on screen: an unfinished partial becomes a final line.
    public mutating func finish() -> String {
        if let event = pending {
            let promoted = TranscriptionEvent(
                text: event.text, isFinal: true, locale: event.locale, timestamp: event.timestamp,
                audioStart: event.audioStart, audioEnd: event.audioEnd
            )
            return render(promoted)
        }
        if liveLineShown {
            liveLineShown = false
            return Self.clearLine
        }
        return ""
    }

    // MARK: Text

    private mutating func renderText(_ event: TranscriptionEvent, text: String) -> String {
        if event.isFinal {
            let hadLiveLine = liveLineShown
            liveLineShown = false
            let prefix = hadLiveLine ? Self.clearLine : ""
            guard !text.isEmpty else { return prefix }
            return "\(prefix)[\(timeString(event.timestamp))] \(text)\n"
        }
        guard interactive, !text.isEmpty else { return "" }
        liveLineShown = true
        return Self.clearLine + Self.tail(text, columns: columns)
    }

    private func timeString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Keeps the end of `text` so that it fits in `columns` terminal cells (wide CJK glyphs count as 2).
    static func tail(_ text: String, columns: Int?) -> String {
        // Keep a safety margin: terminals disagree on the width of "…" and some CJK glyphs, and a
        // single cell of overflow wraps the line, which "\r" can no longer rewrite in place.
        guard let columns, columns > 8 else { return text }
        let budget = columns - 4
        guard displayWidth(text) > budget else { return text }
        var width = 2 // the leading ellipsis, counted as ambiguous-width
        var kept: [Character] = []
        for character in text.reversed() {
            let w = displayWidth(character)
            if width + w > budget { break }
            width += w
            kept.append(character)
        }
        return "…" + String(kept.reversed())
    }

    static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + displayWidth($1) }
    }

    static func displayWidth(_ character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    // MARK: JSONL

    private func jsonLine(_ event: TranscriptionEvent, text: String) -> String {
        var fields = [
            "\"timestamp\":\(Self.jsonString(isoString(event.timestamp)))",
            "\"isFinal\":\(event.isFinal ? "true" : "false")",
            "\"text\":\(Self.jsonString(text))",
            "\"locale\":\(Self.jsonString(event.locale))",
        ]
        if let start = event.audioStart, start.isFinite { fields.append("\"audioStart\":\(Self.number(start))") }
        if let end = event.audioEnd, end.isFinite { fields.append("\"audioEnd\":\(Self.number(end))") }
        return "{" + fields.joined(separator: ",") + "}\n"
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func jsonString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }
}

/// Speech models occasionally fall into a decoding loop and emit the same phrase dozens of times.
/// Collapses a phrase repeated back-to-back (4+ times for 1-2 words, 3+ times for longer phrases) to one copy.
public enum RepetitionGuard {
    public static func collapse(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 6, words.count <= 4000 else { return text }
        var changed = false
        var i = 0
        while i < words.count {
            let maxPeriod = min(40, (words.count - i) / 2)
            if maxPeriod >= 1 {
                for period in 1...maxPeriod {
                    let unit = words[i..<(i + period)]
                    var runs = 1
                    while i + (runs + 1) * period <= words.count,
                          words[(i + runs * period)..<(i + (runs + 1) * period)] == unit {
                        runs += 1
                    }
                    if runs >= (period <= 2 ? 4 : 3) {
                        words.removeSubrange((i + period)..<(i + runs * period))
                        changed = true
                        break
                    }
                }
            }
            i += 1
        }
        return changed ? words.joined(separator: " ") : text
    }
}

public enum StdoutWriter {
    /// Writes and flushes immediately so downstream pipes see every line right away.
    public static func write(_ string: String) {
        guard !string.isEmpty else { return }
        fputs(string, stdout)
        fflush(stdout)
    }
}

/// Thread-safe sink shared by the event loop and the signal handlers; `finish()` is idempotent.
public final class OutputPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var formatter: OutputFormatter
    private let write: @Sendable (String) -> Void
    private let currentColumns: (@Sendable () -> Int?)?
    private var finished = false

    /// `currentColumns` is re-read for every event so a resized terminal never leaves the live line wrapping.
    public init(
        formatter: OutputFormatter,
        currentColumns: (@Sendable () -> Int?)? = nil,
        write: @escaping @Sendable (String) -> Void = StdoutWriter.write
    ) {
        self.formatter = formatter
        self.currentColumns = currentColumns
        self.write = write
    }

    public func handle(_ event: TranscriptionEvent) {
        lock.withLock {
            guard !finished else { return }
            if let currentColumns { formatter.columns = currentColumns() }
            write(formatter.render(event))
        }
    }

    public func finish() {
        lock.withLock {
            guard !finished else { return }
            finished = true
            write(formatter.finish())
        }
    }
}
