import Foundation

/// What the notes of one situation contain, and in which order. A conversation keeps what to remember and do, a meeting
/// keeps decisions and tasks, a talk keeps the key points and the questions raised.
public struct MinutesTemplate: Equatable, Sendable {
    public enum Section: String, CaseIterable, Sendable {
        case summary, keyPoints, decisions, actions, questions
    }

    public let sections: [Section]
    private let limits: [Section: Int]

    /// The most points of a section that are kept for one part of the transcript.
    public func limit(_ section: Section) -> Int { limits[section] ?? 6 }

    public static let conversation = MinutesTemplate(sections: [.summary, .keyPoints, .actions], limits: [.keyPoints: 6, .actions: 5])
    public static let meeting = MinutesTemplate(sections: [.summary, .decisions, .actions, .questions], limits: [.decisions: 6, .actions: 6, .questions: 4])
    public static let seminar = MinutesTemplate(sections: [.summary, .keyPoints, .questions], limits: [.keyPoints: 8, .questions: 5])

    /// Every section (for tests of the shared rules).
    static let full = MinutesTemplate(sections: Section.allCases, limits: [:])

    public static func template(for scenario: Scenario) -> MinutesTemplate {
        switch scenario {
        case .conversation: .conversation
        case .meeting: .meeting
        case .seminar: .seminar
        }
    }
}

/// The text rules of the notes, in one place: whatever the model writes goes through them.
public enum MinutesText {
    private static let empty: Set<String> = [
        "none", "n/a", "na", "nothing", "no", "-", "—", "none found", "no decisions", "no action items",
        "없음", "없습니다", "해당 없음", "해당사항 없음", "찾지 못했습니다", "なし", "ありません", "該当なし", "无", "没有", "无内容", "未找到",
    ]

    /// A role word instead of a name ("user", "사용자"): not who the meeting said will do it.
    private static let generic: Set<String> = [
        "user", "speaker", "the speaker", "someone", "unknown", "me", "you", "i", "we", "they", "he", "she", "participant", "attendee",
        "사용자", "화자", "발표자", "강사", "참석자", "참가자", "누군가", "나", "저", "우리", "상대", "상대방",
        "ユーザー", "話者", "講師", "参加者", "誰か", "私", "私たち", "相手",
        "用户", "说话人", "讲师", "参与者", "某人", "我", "我们", "对方",
    ]

    /// The person of a task as the meeting named them, or nil when the model wrote a role word or nothing.
    public static func person(_ raw: String) -> String? {
        guard let name = tidy(raw), !generic.contains(name.lowercased()) else { return nil }
        return name
    }

    /// One point as it should read: trimmed, on one line, without a bullet or a number in front, without the closing full
    /// stop (a summary keeps it). Nil when nothing meaningful is left.
    public static func tidy(_ raw: String, keepsStop: Bool = false) -> String? {
        var text = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "- ", "• ", "* ", "1. ", "1) ", "(1) "
        if let range = text.range(of: #"^(?:[-•*·]+|\(?\d{1,2}[.)])\s+"#, options: .regularExpression) { text.removeSubrange(range) }
        if !keepsStop { while let last = text.last, ".。".contains(last) { text.removeLast() } }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !empty.contains(text.lowercased()) else { return nil }
        return text
    }

    /// Two points are the same when they differ only in case, spacing or punctuation.
    public static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

/// The instructions the language model is given: one role per situation, the rules for each kind of point, and a short
/// example of the shape wanted. They are written in the language of the notes, because the model answers in the language
/// it is addressed in.
public enum MinutesPrompt {
    public static func instructions(for template: MinutesTemplate, scenario: Scenario, language: SpokenLanguage) -> String {
        let w = words(language)
        var lines = [role(scenario, language), w.faithful, w.lineNumbers]
        for section in template.sections { lines.append(w.rule(section)) }
        let unused = MinutesTemplate.Section.allCases.filter { !template.sections.contains($0) }
        if !unused.isEmpty { lines.append(w.leaveEmpty(unused)) }
        if template.sections.contains(.actions) { lines.append(w.example()) }
        return lines.joined(separator: "\n")
    }

    private struct Words {
        let faithful: String
        let lineNumbers: String
        let rule: (MinutesTemplate.Section) -> String
        let leaveEmpty: ([MinutesTemplate.Section]) -> String
        let example: () -> String
    }

    private static func role(_ scenario: Scenario, _ language: SpokenLanguage) -> String {
        switch (language, scenario) {
        case (.english, .conversation): "You write short notes of a conversation between two people. Write only in English."
        case (.english, .meeting): "You write meeting minutes. Write only in English."
        case (.english, .seminar): "You write notes of a talk the reader only listened to. Write only in English."
        case (.korean, .conversation): "당신은 두 사람의 대화를 짧게 정리합니다. 반드시 한국어로만 쓰세요."
        case (.korean, .meeting): "당신은 회의록 작성자입니다. 반드시 한국어로만 쓰세요."
        case (.korean, .seminar): "당신은 듣기만 한 강연이나 세미나의 노트를 정리합니다. 반드시 한국어로만 쓰세요."
        case (.japanese, .conversation): "あなたは二人の会話を短くまとめます。必ず日本語だけで書いてください。"
        case (.japanese, .meeting): "あなたは議事録の作成者です。必ず日本語だけで書いてください。"
        case (.japanese, .seminar): "あなたは聞くだけだった講演やセミナーのノートをまとめます。必ず日本語だけで書いてください。"
        case (.chinese, .conversation): "你负责简要整理两个人的对话。必须只用简体中文书写。"
        case (.chinese, .meeting): "你是会议纪要的撰写者。必须只用简体中文书写。"
        case (.chinese, .seminar): "你负责整理只是听讲的讲座或研讨会笔记。必须只用简体中文书写。"
        }
    }

    private static func words(_ language: SpokenLanguage) -> Words {
        switch language {
        case .english:
            Words(
                faithful: "Use only what the lines say. Copy names, dates and weekdays exactly. Never invent anything. Write each point as one short sentence about the content itself: do not write \"the transcript\", \"the user\" or \"the speaker\".",
                lineNumbers: "For every point, give the numbers in square brackets at the start of the lines it is based on.",
                rule: { section in
                    switch section {
                    case .summary: "summary: one or two complete sentences, not a list of keywords."
                    case .keyPoints: "keyPoints: the most important things that were said, each on its own."
                    case .decisions: "decisions: only what was clearly agreed or announced as decided. A question, a proposal or something still being reviewed is not a decision."
                    case .actions: "actions: what someone promised or was asked to do. Put the person in owner only when a name is said (never \"user\" or \"speaker\"), and the day or date in due exactly as said; leave them empty when not said."
                    case .questions: "questions: matters left open or questions raised and not answered."
                    }
                },
                leaveEmpty: { "Leave these empty: " + $0.map(\.rawValue).joined(separator: ", ") + "." },
                example: { "Example of one task: text \"Update the release notes\", owner \"Maria\", due \"Wednesday\", lines [4]." }
            )
        case .korean:
            Words(
                faithful: "아래 줄에 있는 내용만 쓰세요. 이름, 날짜, 요일은 나온 그대로 옮기세요. 없는 내용을 지어내지 마세요. 항목은 내용 자체를 설명하는 짧은 한 문장으로 쓰고, \"대화록\", \"사용자\", \"화자\"라는 말은 쓰지 마세요.",
                lineNumbers: "항목마다 근거가 된 줄의 대괄호 번호를 적으세요.",
                rule: { section in
                    switch section {
                    case .summary: "summary: 키워드 나열이 아니라 한두 개의 완성된 문장."
                    case .keyPoints: "keyPoints: 말한 내용 중 가장 중요한 것을 하나씩."
                    case .decisions: "decisions: 분명히 합의했거나 결정됐다고 알린 것만. 질문, 제안, 아직 검토 중인 일은 결정이 아닙니다."
                    case .actions: "actions: 누군가 하겠다고 했거나 하라고 요청받은 일. 사람은 이름이 나온 경우에만 owner에 적고(\"사용자\", \"화자\"는 쓰지 마세요), 날짜나 요일은 due에 들은 그대로 적고, 말하지 않았으면 비워 두세요."
                    case .questions: "questions: 답이 나오지 않고 남은 일이나 제기된 질문."
                    }
                },
                leaveEmpty: { "다음 항목은 비워 두세요: " + $0.map(\.rawValue).joined(separator: ", ") + "." },
                example: { "할 일 한 가지의 예: text \"릴리스 노트 업데이트\", owner \"민수\", due \"수요일\", lines [4]." }
            )
        case .japanese:
            Words(
                faithful: "下の行にある内容だけを書いてください。名前、日付、曜日はそのまま写し、ないことを作らないでください。各項目は内容そのものを述べる短い一文にし、「書き起こし」「ユーザー」「話者」という言葉は使わないでください。",
                lineNumbers: "各項目に、根拠にした行の角かっこの番号を書いてください。",
                rule: { section in
                    switch section {
                    case .summary: "summary: キーワードの羅列ではなく、一、二文の完結した文章。"
                    case .keyPoints: "keyPoints: 話された内容のうち最も重要なことを一つずつ。"
                    case .decisions: "decisions: はっきり合意された、または決定として告げられたことだけ。質問、提案、検討中のことは決定ではありません。"
                    case .actions: "actions: 誰かがやると言った、またはやるよう頼まれたこと。人はowner、日付や曜日はdueに聞いたとおりに書き、言われていなければ空にしてください。"
                    case .questions: "questions: 答えが出ずに残ったことや、出された質問。"
                    }
                },
                leaveEmpty: { "次の項目は空にしてください：" + $0.map(\.rawValue).joined(separator: "、") + "。" },
                example: { "やることの例：text「リリースノートを更新」、owner「田中」、due「水曜日」、lines [4]。" }
            )
        case .chinese:
            Words(
                faithful: "只写下面各行里有的内容。姓名、日期和星期必须照原样写，不要编造。每一项写成陈述内容本身的简短一句话，不要出现“记录”“用户”“说话人”这样的词。",
                lineNumbers: "每一项都要写出所依据的行号（方括号中的数字）。",
                rule: { section in
                    switch section {
                    case .summary: "summary：一两句完整的话，不要罗列关键词。"
                    case .keyPoints: "keyPoints：所说内容中最重要的几点，每点单独列出。"
                    case .decisions: "decisions：只写明确同意或宣布已决定的事。提问、提议、仍在审核的事项不是决定。"
                    case .actions: "actions：有人承诺或被要求去做的事。人写在owner，日期或星期写在due，按原话；没说就留空。"
                    case .questions: "questions：没有得到答案而遗留的事项，或被提出的问题。"
                    }
                },
                leaveEmpty: { "以下项目请留空：" + $0.map(\.rawValue).joined(separator: "、") + "。" },
                example: { "待办事项示例：text“更新发布说明”，owner“小王”，due“周三”，lines [4]。" }
            )
        }
    }
}
