import Foundation

/// A draft of meeting minutes made from a saved transcript. Every decision and task points at the transcript lines it
/// came from, so a reader can check it; a point with no valid line is marked instead of presented as fact.
public struct MeetingMinutes: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var text: String
        /// 1-based numbers of the transcript lines (`ScriptEntry` positions) the point is based on.
        public var lines: [Int]
        /// For a task: who does it and by when, as said in the meeting. Nil when the meeting did not say.
        public var owner: String?
        public var due: String?

        public init(text: String, lines: [Int], owner: String? = nil, due: String? = nil) {
            self.text = text
            self.lines = lines
            self.owner = owner
            self.due = due
        }

        /// `Maria — update the release notes (Wednesday)`: the one way a task is written.
        public var displayText: String {
            var out = text
            if let owner { out = "\(owner) — \(out)" }
            if let due { out += " (\(due))" }
            return out
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
    /// What was said that is worth keeping (a conversation, a talk) and what was left open.
    public var keyPoints: [Point]
    public var questions: [Point]
    /// Transcript lines the model declined to read; the notes say so instead of looking complete.
    public var unread: [Int]

    public init(parts: [Part], decisions: [Point], actions: [Point], keyPoints: [Point] = [], questions: [Point] = [], unread: [Int] = []) {
        self.parts = parts
        self.decisions = decisions
        self.actions = actions
        self.keyPoints = keyPoints
        self.questions = questions
        self.unread = unread
    }

    /// A decision or a task rests on a few sentences. A point that cites more is a summary of a stretch of the meeting.
    public static let maxCitedLines = 4
    public static let maxCitedQuestionLines = 3

    /// Normalizes what the model wrote, so the notes read the same whatever the model's habits (a point that cites no existing line is dropped):
    /// - text is trimmed, bullets, numbering and closing full stops removed, and empty answers ("None", "없음") dropped;
    /// - line numbers that do not exist are dropped, once each and in order;
    /// - a point that repeats another one (ignoring case and punctuation), repeats a summary, or cites too many lines to be one
    ///   point is dropped; the same sentence as a decision and as a task stays a task;
    /// - points follow the order of the meeting.
    public func validated(entryCount: Int, template: MinutesTemplate = .meeting) -> MeetingMinutes {
        let summaries = Set(parts.map { MinutesText.key($0.summary) })
        /// `other` holds the points already placed in another list: (text, owner).
        func clean(_ points: [Point], excluding other: [(String, String?)] = [], limit: Int, maxLines: Int = Self.maxCitedLines) -> [Point] {
            var seen = other
            let kept: [Point] = points.compactMap { point -> Point? in
                guard let text = MinutesText.tidy(point.text) else { return nil }
                let lines = Array(Set(point.lines.filter { $0 >= 1 && $0 <= entryCount })).sorted()
                // A point that cites no line is, in practice, the model filling a list (measured: nearly all of them are invented).
                guard !lines.isEmpty, lines.count <= maxLines else { return nil }
                let owner = point.owner.flatMap { MinutesText.person($0) }
                // The same words for two different people are two tasks ("Dana sends the report", "Tom sends the report").
                let duplicate = seen.contains { other in
                    if let a = other.1?.lowercased(), let b = owner?.lowercased(), a != b { return false }
                    return MinutesText.nearDuplicates(other.0, text)
                }
                guard !summaries.contains(MinutesText.key(text)), !duplicate else { return nil }
                seen.append((text, owner))
                return Point(text: owner.map { MinutesText.withoutPerson(text, $0) } ?? text, lines: lines, owner: owner, due: point.due.flatMap { MinutesText.tidy($0) })
            }
            // Points follow the meeting; one without a source goes last.
            let ordered = kept.enumerated().sorted { a, b in
                let x = a.element.lines.first ?? Int.max, y = b.element.lines.first ?? Int.max
                return x == y ? a.offset < b.offset : x < y
            }.map(\.element)
            return Array(ordered.prefix(limit))
        }
        // Who and when belong to tasks only; in the other lists a name would just repeat the speaker.
        func withoutWho(_ points: [Point]) -> [Point] { points.map { Point(text: $0.text, lines: $0.lines) } }
        func texts(_ points: [Point]) -> [(String, String?)] { points.map { ($0.text, $0.owner) } }
        // The limits are per part of the transcript; a long meeting read in several parts keeps that many from each.
        let scale = max(1, parts.count)
        func cap(_ section: MinutesTemplate.Section) -> Int { template.limit(section) * scale }
        // A list the situation does not show must not take part in the comparison: it would remove visible points.
        func shown(_ section: MinutesTemplate.Section, _ points: [Point]) -> [Point] { template.sections.contains(section) ? points : [] }
        // A "decision" that says the matter is still open is a question.
        let pending = shown(.decisions, self.decisions).filter { MinutesText.looksPending($0.text) }
        let settled = shown(.decisions, self.decisions).filter { !MinutesText.looksPending($0.text) }
        // A sentence that fits several lists belongs to the first of: task, decision, key point, open question.
        let actions = clean(shown(.actions, self.actions), limit: cap(.actions))
        let decisions = withoutWho(clean(settled, excluding: texts(actions), limit: cap(.decisions)))
        let keyPoints = withoutWho(clean(shown(.keyPoints, self.keyPoints), excluding: texts(actions) + texts(decisions), limit: cap(.keyPoints)))
        // A question rests on a line or two; one that cites more is a summary of a stretch.
        let questions = withoutWho(clean(shown(.questions, self.questions) + (template.sections.contains(.questions) ? pending : []),
                                         excluding: texts(actions) + texts(decisions) + texts(keyPoints),
                                         limit: cap(.questions), maxLines: Self.maxCitedQuestionLines))
        return MeetingMinutes(
            parts: parts.compactMap { part in
                MinutesText.tidy(part.summary, keepsStop: true).map { Part(lines: part.lines, summary: $0) }
            },
            decisions: decisions, actions: actions, keyPoints: keyPoints, questions: questions,
            unread: Array(Set(unread.filter { $0 >= 1 && $0 <= entryCount })).sorted()
        )
    }

    /// A task keeps the person and the day only if they were said: a small model fills these two slots from the example it was
    /// shown, or from thin air. A name must occur in the transcript; a day must too, unless the notes are in another language than
    /// the transcript (then "Tuesday" legitimately becomes "화요일").
    public func grounded(in entries: [ScriptEntry]) -> MeetingMinutes {
        let corpus = entries.map(\.text).joined(separator: " ").lowercased()
        let corpusIsWide = TextScript.cjkRatio(corpus) > 0.3
        /// A Latin word must stand as a word of the transcript (not "Jo" inside "job"); a Korean, Japanese or Chinese word may sit
        /// inside a longer one (a particle follows a name), and may be a single character.
        func occurs(_ word: String) -> Bool {
            let lower = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?()\"'"))
            if TextScript.cjkRatio(lower) > 0.5 { return corpus.contains(lower) }
            guard lower.count >= 2 else { return false }
            var start = corpus.startIndex
            while let range = corpus.range(of: lower, range: start..<corpus.endIndex) {
                let before = range.lowerBound == corpus.startIndex ? nil : corpus[corpus.index(before: range.lowerBound)]
                let after = range.upperBound == corpus.endIndex ? nil : corpus[range.upperBound]
                if !(before?.isLetter ?? false), !(after?.isLetter ?? false) || after == "'" || after == "\u{2019}" { return true }
                start = range.upperBound
            }
            return false
        }
        func words(_ phrase: String) -> [String] { phrase.split(whereSeparator: \.isWhitespace).map(String.init) }
        var copy = self
        copy.actions = actions.map { point in
            var grounded = point
            // One word of the name is enough ("Dana Lee" when only "Dana" was said); "씨" and "님" are not part of a name.
            if let owner = point.owner, !words(owner).filter({ !["씨", "님"].contains($0) }).contains(where: occurs) { grounded.owner = nil }
            // Another language than the transcript legitimately translates the day ("Tuesday" becomes "화요일"), but a Latin day in
            // notes about a Korean transcript can only be invented.
            if let due = point.due, !((TextScript.cjkRatio(due) > 0.3) && !corpusIsWide), !words(due).allSatisfy(occurs) { grounded.due = nil }
            return grounded
        }
        return copy
    }

    public var isEmpty: Bool { parts.isEmpty && decisions.isEmpty && actions.isEmpty && keyPoints.isEmpty && questions.isEmpty && unread.isEmpty }
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
        let draft, summary, keyPoints, decisions, actions, questions, none, noSource, lines, unread: String
    }

    static func words(for language: SpokenLanguage) -> Words {
        switch language {
        case .english:
            Words(draft: "Draft made on this Mac by an on-device language model. Check every point against the lines it cites before relying on it.",
                  summary: "Summary", keyPoints: "Key points", decisions: "Decisions", actions: "Action items", questions: "Open questions",
                  none: "None found.", noSource: "no source line", lines: "lines", unread: "The model did not read these lines, so the notes may be missing something from them:")
        case .korean:
            Words(draft: "이 Mac 안의 언어 모델이 만든 초안입니다. 믿고 쓰기 전에 각 항목이 가리키는 줄과 맞는지 확인하세요.",
                  summary: "요약", keyPoints: "핵심 내용", decisions: "결정 사항", actions: "할 일", questions: "남은 질문",
                  none: "찾지 못했습니다.", noSource: "근거 줄 없음", lines: "줄", unread: "모델이 읽지 않은 줄이 있어 이 줄들의 내용이 빠졌을 수 있습니다:")
        case .japanese:
            Words(draft: "このMacの中の言語モデルが作った下書きです。使う前に、各項目が示す行と合っているか確認してください。",
                  summary: "要約", keyPoints: "要点", decisions: "決定事項", actions: "やること", questions: "未解決の質問",
                  none: "見つかりませんでした。", noSource: "根拠の行なし", lines: "行", unread: "モデルが読まなかった行があるため、これらの行の内容が抜けている可能性があります：")
        case .chinese:
            Words(draft: "这是由本机上的语言模型生成的草稿。使用前请对照每一项所引用的行进行核实。",
                  summary: "摘要", keyPoints: "要点", decisions: "决定事项", actions: "待办事项", questions: "遗留问题",
                  none: "未找到。", noSource: "没有依据行", lines: "行", unread: "模型没有读取这些行，因此这些行的内容可能缺失：")
        }
    }

    /// The heading of a section of the notes.
    public static func heading(_ section: MinutesTemplate.Section, language: SpokenLanguage) -> String {
        let w = words(for: language)
        switch section {
        case .summary: return w.summary
        case .keyPoints: return w.keyPoints
        case .decisions: return w.decisions
        case .actions: return w.actions
        case .questions: return w.questions
        }
    }

    /// The points of a section of `minutes`.
    public static func points(_ section: MinutesTemplate.Section, in minutes: MeetingMinutes) -> [MeetingMinutes.Point] {
        switch section {
        case .summary: []
        case .keyPoints: minutes.keyPoints
        case .decisions: minutes.decisions
        case .actions: minutes.actions
        case .questions: minutes.questions
        }
    }

    public static func render(_ minutes: MeetingMinutes, entries: [ScriptEntry], title: String, language: SpokenLanguage, template: MinutesTemplate = .meeting) -> String {
        let w = words(for: language)
        func reference(_ lines: [Int]) -> String {
            guard !lines.isEmpty else { return " ⚠︎ \(w.noSource)" }
            let shown = lines.prefix(4).map { number -> String in
                let clock = TranscriptExport.timecode(entries[number - 1].offset, comma: false).prefix(8)
                return "[\(number)] \(clock)"
            }
            return " (\(w.lines) " + shown.joined(separator: ", ") + (lines.count > 4 ? " …" : "") + ")"
        }
        func list(_ points: [MeetingMinutes.Point]) -> String {
            points.isEmpty ? "\(w.none)\n" : points.map { "- \($0.displayText)\(reference($0.lines))\n" }.joined()
        }
        var out = "# \(title)\n\n> \(w.draft)\n"
        for section in template.sections {
            out += "\n## \(heading(section, language: language))\n\n"
            if section == .summary {
                if minutes.parts.isEmpty {
                    out += "\(w.none)\n"
                } else if minutes.parts.count == 1 {
                    out += "\(minutes.parts[0].summary)\n"
                } else {
                    for part in minutes.parts {
                        out += "- \(part.summary) (\(w.lines) \(part.lines.lowerBound)–\(part.lines.upperBound))\n"
                    }
                }
            } else {
                out += list(points(section, in: minutes))
            }
        }
        if !minutes.unread.isEmpty {
            out += "\n> ⚠︎ \(w.unread) " + minutes.unread.map { "[\($0)]" }.joined(separator: " ") + "\n"
        }
        return out
    }
}
