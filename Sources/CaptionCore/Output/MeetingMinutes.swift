import Foundation

/// A draft of meeting minutes made from a saved transcript. Every decision and task points at the transcript lines it
/// came from, so a reader can check it; a point with no valid line is marked instead of presented as fact.
public struct MeetingMinutes: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var text: String
        /// 1-based numbers of the transcript lines (`ScriptEntry` positions) the point is based on.
        public var lines: [Int]

        public init(text: String, lines: [Int]) {
            self.text = text
            self.lines = lines
        }
    }

    /// One summary per part of the transcript (a long meeting is read in parts), with the lines the part covers.
    public struct Part: Equatable, Sendable {
        public var lines: ClosedRange<Int>
        public var summary: String

        public init(lines: ClosedRange<Int>, summary: String) {
            self.lines = lines
            self.summary = summary
        }
    }

    public var parts: [Part]
    public var decisions: [Point]
    public var actions: [Point]

    public init(parts: [Part], decisions: [Point], actions: [Point]) {
        self.parts = parts
        self.decisions = decisions
        self.actions = actions
    }

    /// A decision or a task rests on a few sentences. A point that cites more is a summary of a stretch of the meeting.
    public static let maxCitedLines = 8

    /// Keeps only line numbers that exist, once each and in order. Drops points that say nothing, repeat another one,
    /// repeat a summary (a small model fills an empty list that way), or cite too many lines to be one decision or task.
    public func validated(entryCount: Int) -> MeetingMinutes {
        let summaries = Set(parts.map { $0.summary.trimmingCharacters(in: .whitespacesAndNewlines) })
        func clean(_ points: [Point]) -> [Point] {
            var seen = Set<String>()
            return points.compactMap { point in
                let text = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !summaries.contains(text), seen.insert(text).inserted else { return nil }
                let lines = Array(Set(point.lines.filter { $0 >= 1 && $0 <= entryCount })).sorted()
                guard lines.count <= Self.maxCitedLines else { return nil }
                return Point(text: text, lines: lines)
            }
        }
        return MeetingMinutes(
            parts: parts.filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            decisions: clean(decisions),
            actions: clean(actions)
        )
    }

    public var isEmpty: Bool { parts.isEmpty && decisions.isEmpty && actions.isEmpty }
}

/// Cuts a transcript into parts small enough for the on-device model and writes them with line numbers it can cite.
public enum MinutesSource {
    /// A part of the transcript: the entries `start..<end` (0-based).
    public struct Chunk: Equatable, Sendable {
        public var start: Int
        public var end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }

        public var lines: ClosedRange<Int> { (start + 1)...end }
    }

    /// Characters per part. The model's window is small and CJK text takes far more tokens per character.
    public static func budget(for entries: ArraySlice<ScriptEntry>) -> Int {
        let sample = entries.map(\.text).joined()
        return TextScript.cjkRatio(sample) > 0.3 ? 1_200 : 3_200
    }

    /// Consecutive entries, each part within the budget (a single longer sentence is a part of its own).
    public static func chunks(_ entries: [ScriptEntry]) -> [Chunk] {
        guard !entries.isEmpty else { return [] }
        let limit = budget(for: entries[...])
        var chunks: [Chunk] = []
        var start = 0, used = 0
        for (index, entry) in entries.enumerated() {
            let cost = entry.text.count + 12
            if used + cost > limit, index > start {
                chunks.append(Chunk(start: start, end: index))
                start = index
                used = 0
            }
            used += cost
        }
        chunks.append(Chunk(start: start, end: entries.count))
        return chunks
    }

    /// `[12] 00:02:21 sentence`, one per line, numbered as in the whole transcript.
    public static func numbered(_ entries: [ScriptEntry], _ chunk: Chunk) -> String {
        (chunk.start..<chunk.end).map { index in
            let entry = entries[index]
            let speaker = entry.language.map { " (\($0))" } ?? ""
            return "[\(index + 1)] \(TranscriptExport.timecode(entry.offset, comma: false).prefix(8))\(speaker) \(entry.text)"
        }.joined(separator: "\n")
    }
}

/// Writes the minutes as a Markdown file with the headings in the reader's language.
public enum MinutesMarkdown {
    struct Words {
        let draft, summary, decisions, actions, none, noSource, lines: String
    }

    static func words(for language: SpokenLanguage) -> Words {
        switch language {
        case .english:
            Words(draft: "Draft made on this Mac by an on-device language model. Check every point against the lines it cites before relying on it.",
                  summary: "Summary", decisions: "Decisions", actions: "Action items", none: "None found.",
                  noSource: "no source line", lines: "lines")
        case .korean:
            Words(draft: "이 Mac 안의 언어 모델이 만든 초안입니다. 믿고 쓰기 전에 각 항목이 가리키는 줄과 맞는지 확인하세요.",
                  summary: "요약", decisions: "결정 사항", actions: "할 일", none: "찾지 못했습니다.",
                  noSource: "근거 줄 없음", lines: "줄")
        case .japanese:
            Words(draft: "このMacの中の言語モデルが作った下書きです。使う前に、各項目が示す行と合っているか確認してください。",
                  summary: "要約", decisions: "決定事項", actions: "やること", none: "見つかりませんでした。",
                  noSource: "根拠の行なし", lines: "行")
        case .chinese:
            Words(draft: "这是由本机上的语言模型生成的草稿。使用前请对照每一项所引用的行进行核实。",
                  summary: "摘要", decisions: "决定事项", actions: "待办事项", none: "未找到。",
                  noSource: "没有依据行", lines: "行")
        }
    }

    public static func render(_ minutes: MeetingMinutes, entries: [ScriptEntry], title: String, language: SpokenLanguage) -> String {
        let w = words(for: language)
        func reference(_ lines: [Int]) -> String {
            guard !lines.isEmpty else { return " ⚠︎ \(w.noSource)" }
            let shown = lines.map { number -> String in
                let clock = TranscriptExport.timecode(entries[number - 1].offset, comma: false).prefix(8)
                return "[\(number)] \(clock)"
            }
            return " (\(w.lines) " + shown.joined(separator: ", ") + ")"
        }
        func list(_ points: [MeetingMinutes.Point]) -> String {
            points.isEmpty ? "\(w.none)\n" : points.map { "- \($0.text)\(reference($0.lines))\n" }.joined()
        }
        var out = "# \(title)\n\n> \(w.draft)\n\n## \(w.summary)\n\n"
        if minutes.parts.isEmpty {
            out += "\(w.none)\n"
        } else if minutes.parts.count == 1 {
            out += "\(minutes.parts[0].summary)\n"
        } else {
            for part in minutes.parts {
                out += "- \(part.summary) (\(w.lines) \(part.lines.lowerBound)–\(part.lines.upperBound))\n"
            }
        }
        out += "\n## \(w.decisions)\n\n\(list(minutes.decisions))\n## \(w.actions)\n\n\(list(minutes.actions))"
        return out
    }
}
