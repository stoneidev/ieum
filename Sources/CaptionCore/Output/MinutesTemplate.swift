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
        "none", "n/a", "nothing", "—", "none found", "no decisions", "no action items",
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
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !empty.contains(name.lowercased()), !generic.contains(name.lowercased()) else { return nil }
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
        guard text.contains(where: { $0.isLetter || $0.isNumber }), !empty.contains(text.lowercased()) else { return nil }
        return text
    }

    /// A task is written with its person beside it, so the person is not repeated in front of the action
    /// ("Priya — Priya will fix it" becomes "Priya — fix it"). Only a name that stands alone is removed: "Annual review" and
    /// "민수 이사에게 보고" keep their first word.
    public static func withoutPerson(_ text: String, _ owner: String) -> String {
        let name = owner.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? owner
        guard !name.isEmpty, text.lowercased().hasPrefix(name.lowercased()) else { return text }
        let rest = String(text.dropFirst(name.count))
        func standsAlone(_ remainder: Substring) -> Bool { remainder.isEmpty || remainder.first?.isWhitespace == true }
        var remainder: Substring = rest[...]
        if let first = remainder.first, first.isWhitespace {
            remainder = remainder.drop(while: \.isWhitespace)
            // "민수 씨가 …", "민수 씨는 …", "민수 씨, …"
            if remainder.hasPrefix("씨") {
                remainder = remainder.dropFirst()
                for particle in ["께서", "가", "는", "도"] where remainder.hasPrefix(particle) && standsAlone(remainder.dropFirst(particle.count)) {
                    remainder = remainder.dropFirst(particle.count); break
                }
                guard standsAlone(remainder) || remainder.first.map({ ",:".contains($0) }) == true else { return text }
            } else if let modal = ["will", "should", "is going to", "must", "can"].first(where: { remainder.lowercased().hasPrefix($0 + " ") }) {
                remainder = remainder.dropFirst(modal.count)
            } else if !(remainder.first.map { "—-:,".contains($0) } ?? false) {
                return text
            }
        } else if let first = remainder.first, "—-:,".contains(first) {
            // "Priya: …", "Priya — …"
        } else if let particle = ["께서", "가", "이", "는", "은"].first(where: { remainder.hasPrefix($0) && standsAlone(remainder.dropFirst($0.count)) }) {
            // a Korean particle glued to the name and then a space: "Priya가 패치를 …"
            remainder = remainder.dropFirst(particle.count)
        } else {
            return text
        }
        let cleaned = String(remainder).trimmingCharacters(in: CharacterSet(charactersIn: " —-:,")).trimmingCharacters(in: .whitespaces)
        return cleaned.count >= 2 ? cleaned : text
    }

    /// Phrases that say a matter is still open. A "decision" that carries one is a question. Latin phrases must stand as words.
    private static let pendingLatin = [
        "not yet decided", "not decided", "undecided", "hasn't been decided", "has not been decided", "yet to decide", "cannot decide",
        "can't decide", "can not decide", "no decision", "to be decided", "not been decided", "unable to decide",
    ]
    private static let pendingCJK = [
        "아직 결정되지", "결정되지 않", "결정하지 못", "결정할 수 없", "결정 보류", "정해지지 않", "아직 미정", "미정입니다", "미정이다", "미정임",
        "決まっていない", "決定していない", "まだ未定", "未定です", "決められない",
        "尚未决定", "还没决定", "未确定", "尚未确定", "暂不决定", "还没有决定", "无法决定",
    ]

    public static func looksPending(_ text: String) -> Bool {
        let lower = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if pendingCJK.contains(where: { lower.contains($0) }) { return true }
        return pendingLatin.contains { marker in
            var searchStart = lower.startIndex
            while let range = lower.range(of: marker, range: searchStart..<lower.endIndex) {
                let before = range.lowerBound == lower.startIndex ? nil : lower[lower.index(before: range.lowerBound)]
                let after = range.upperBound == lower.endIndex ? nil : lower[range.upperBound]
                if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return true }
                searchStart = range.upperBound
            }
            return false
        }
    }

    /// The numbers in a text, in order ("14 March", "3천만원" → 14 / 3).
    private static func numbers(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }

    /// Two points say the same thing when one contains the other (ignoring case and punctuation) or they share most of their
    /// letters, and they mention the same numbers (two dates are two points).
    public static func nearDuplicates(_ a: String, _ b: String) -> Bool {
        let x = key(a), y = key(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        guard numbers(a) == numbers(b) else { return false }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        // Korean, Japanese and Chinese say more in fewer characters
        if short.count >= (TextScript.cjkRatio(short) > 0.5 ? 5 : 8), long.contains(short) { return true }
        func pairs(_ text: String) -> Set<String> {
            let chars = Array(text)
            guard chars.count > 1 else { return Set([text]) }
            return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
        }
        let p = pairs(x), q = pairs(y)
        return Double(p.intersection(q).count) / Double(max(p.union(q).count, 1)) >= 0.85
    }

    /// Two points are the same when they differ only in case, spacing or punctuation.
    public static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

/// The instructions the language model is given. They are written in the language of the notes, because the model answers in the
/// language it is addressed in, and they have the parts a careful minute-taker would want to be told: what each list is (and is
/// not), what to cite, what never to invent, and one worked example that has nothing to do with the transcript.
public enum MinutesPrompt {
    public static func instructions(for template: MinutesTemplate, scenario: Scenario, language: SpokenLanguage) -> String {
        let w = Wording.of(language)
        var out: [String] = [w.role(scenario), w.input]
        out.append(w.fieldsTitle)
        for section in MinutesTemplate.Section.allCases where template.sections.contains(section) {
            out.append(w.field(section, scenario))
        }
        let unused = MinutesTemplate.Section.allCases.filter { !template.sections.contains($0) }
        if !unused.isEmpty { out.append(w.leaveEmpty(unused)) }
        out.append(w.rulesTitle)
        out += w.rules
        out.append(w.exampleTitle)
        out += example(w, template: template, scenario: scenario)
        return out.joined(separator: "\n")
    }

    // MARK: Example

    /// The example shows the shape of the answer on a transcript that has nothing to do with real ones: another subject,
    /// invented names, so there is nothing in it worth copying (the instructions also say so).
    private static func example(_ w: Wording, template: MinutesTemplate, scenario: Scenario) -> [String] {
        let sample = scenario == .seminar ? w.talkExample : w.meetingExample
        var lines = sample.transcript
        lines.append(w.notesLabel)
        for section in MinutesTemplate.Section.allCases where template.sections.contains(section) {
            if let text = sample.answer[section] { lines.append(text) }
        }
        return lines
    }

    struct Sample: Sendable {
        let transcript: [String]
        let answer: [MinutesTemplate.Section: String]
    }

    /// Everything that differs between languages.
    struct Wording: Sendable {
        let role: @Sendable (Scenario) -> String
        let input: String
        let fieldsTitle: String
        let field: @Sendable (MinutesTemplate.Section, Scenario) -> String
        let leaveEmpty: @Sendable ([MinutesTemplate.Section]) -> String
        let rulesTitle: String
        let rules: [String]
        let exampleTitle: String
        let notesLabel: String
        let meetingExample: Sample
        let talkExample: Sample

        static func of(_ language: SpokenLanguage) -> Wording {
            switch language {
            case .english: english
            case .korean: korean
            case .japanese: japanese
            case .chinese: chinese
            }
        }
    }

    // MARK: English

    private static let english = Wording(
        role: { scenario in
            switch scenario {
            case .conversation: "You write short notes of a conversation between two people, for one of them. Write only in English."
            case .meeting: "You write meeting minutes for a person who could not follow every word. Write only in English."
            case .seminar: "You write notes of a talk for a person who only listened. Write only in English."
            }
        },
        input: "The input is a transcript made by speech recognition. Each line is \"[number] time text\". Ignore stumbles, fillers and repeated words.",
        fieldsTitle: "Fill these fields:",
        field: { section, scenario in
            switch section {
            case .summary: "- summary: one or two complete sentences saying what this part was about. Not a list of keywords."
            case .keyPoints:
                scenario == .seminar
                    ? "- keyPoints: the main claims, explanations, numbers and examples the speaker gave, one per item."
                    : "- keyPoints: what was said that is worth remembering (plans, arrangements, facts), one per item."
            case .decisions: "- decisions: only what the people clearly settled (\"let's go with B\", \"that's decided\", \"we will not do X\" after they agreed). NOT a decision: an option or proposal, an opinion, a question, something still under review or waiting for approval, and anything handed to a person to do (that is an action)."
            case .actions: "- actions: something a person is to do after this, because they promised (\"I'll send it\") or were asked and accepted (\"X, please do Y by Friday\" with a yes is an action for X). text = the action alone, without repeating the person or the date. owner = the person's name, only if a name is said; otherwise empty. due = the day or date exactly as said; otherwise empty. A wish with nobody responsible (\"someone should…\") is not an action; leave it out or put it in questions."
            case .questions:
                scenario == .seminar
                    ? "- questions: questions that the audience really asked in the lines, with the short answer if one was given, and ones the speaker could not answer or promised to answer later. If nobody asked, leave it empty; never make questions up."
                    : "- questions: matters left open: asked and not answered, postponed to next time, or waiting for approval or information."
            }
        },
        leaveEmpty: { "Leave these empty: " + $0.map(\.rawValue).joined(separator: ", ") + "." },
        rulesTitle: "Rules:",
        rules: [
            "1. Use only what the lines say. Never invent a name, a date, a number or a decision. If nothing fits a field, leave it empty.",
            "2. lines = the numbers of the one to three lines where it is said. Never cite more than three.",
            "3. Write each item as one short plain statement of the content, as a secretary would (for example \"The deadline moved to Friday\"), without saying how you know it.",
            "4. Put a fact in one list only. A pending matter is a question, not a decision. Several people may each get their own action.",
            "5. Copy names, numbers, weekdays and dates exactly as spoken.",
        ],
        exampleTitle: "Example of the shape of an answer. It is about something unrelated: never copy its words, names or dates.",
        notesLabel: "Notes:",
        meetingExample: Sample(
            transcript: [
                "Lines:",
                "[1] 00:00:05 Where should we hold the offsite?",
                "[2] 00:00:12 One option is the lake house, the other is a city hotel.",
                "[3] 00:00:20 The hotel is cheaper, so let's book the hotel.",
                "[4] 00:00:28 Okay. Lena, please send the invitations by Thursday.",
                "[5] 00:00:33 Sure, I'll do that.",
                "[6] 00:00:36 And I'll reserve the room tomorrow.",
                "[7] 00:00:40 Do we still need a caterer? I'm not sure yet.",
            ],
            answer: [
                .summary: "summary: They chose the venue for the offsite and handed out the invitations.",
                .decisions: "decisions: {text: \"Book the city hotel for the offsite\", lines: [3]}",
                .actions: "actions: {text: \"Send the invitations\", owner: \"Lena\", due: \"Thursday\", lines: [4, 5]} {text: \"Reserve the room\", owner: \"\", due: \"tomorrow\", lines: [6]}",
                .questions: "questions: {text: \"Whether a caterer is still needed\", lines: [7]}",
                .keyPoints: "keyPoints: {text: \"The hotel costs less than the lake house\", lines: [2, 3]}",
            ]
        ),
        talkExample: Sample(
            transcript: [
                "Lines:",
                "[1] 00:00:04 Bees see ultraviolet light, which we cannot.",
                "[2] 00:00:11 Many flowers have patterns that only show up in ultraviolet, like landing strips.",
                "[3] 00:00:19 Questions? Do bees see red? Not really, they see it as dark.",
            ],
            answer: [
                .summary: "summary: The talk explained how bees see flowers.",
                .keyPoints: "keyPoints: {text: \"Bees see ultraviolet light\", lines: [1]} {text: \"Flower patterns visible only in ultraviolet guide bees\", lines: [2]}",
                .questions: "questions: {text: \"Do bees see red? Not really: they see it as dark\", lines: [3]}",
            ]
        )
    )

    // MARK: Korean

    private static let korean = Wording(
        role: { scenario in
            switch scenario {
            case .conversation: "당신은 두 사람의 대화를, 그중 한 사람을 위해 짧게 정리합니다. 반드시 한국어로만 쓰세요."
            case .meeting: "당신은 모든 말을 따라가지 못한 사람을 위해 회의록을 씁니다. 반드시 한국어로만 쓰세요."
            case .seminar: "당신은 듣기만 한 사람을 위해 강연 노트를 씁니다. 반드시 한국어로만 쓰세요."
            }
        },
        input: "입력은 음성 인식으로 만든 기록입니다. 각 줄은 \"[번호] 시각 내용\"입니다. 더듬거림, 군말, 반복은 무시하세요.",
        fieldsTitle: "다음 항목을 채우세요:",
        field: { section, scenario in
            switch section {
            case .summary: "- summary: 이 부분이 무엇에 관한 것인지 완성된 한두 문장. 키워드 나열은 안 됩니다."
            case .keyPoints:
                scenario == .seminar
                    ? "- keyPoints: 강연자가 말한 주요 주장, 설명, 수치, 예시를 항목 하나에 하나씩."
                    : "- keyPoints: 기억해 둘 만한 내용(계획, 약속, 사실)을 항목 하나에 하나씩."
            case .decisions: "- decisions: 사람들이 분명하게 확정한 것만(\"~로 하죠\", \"그렇게 결정하겠습니다\", 합의 뒤의 \"~는 하지 않기로\"). 결정이 아닌 것: 선택지나 제안, 의견, 질문, 아직 검토 중이거나 승인을 기다리는 일, 그리고 누군가에게 맡긴 일(그것은 할 일입니다)."
            case .actions: "- actions: 이후에 누군가 해야 하는 일. 본인이 하겠다고 했거나(\"제가 보내겠습니다\") 부탁을 받아 수락한 것(\"○○ 씨가 금요일까지 해 주세요\"에 \"네\"라고 답하면 ○○ 씨의 할 일). text = 할 일만 적고 사람과 날짜는 text에 반복하지 않습니다. owner = 이름이 나온 경우에만 그 이름, 아니면 비워 둡니다. due = 말한 날짜나 요일 그대로, 없으면 비워 둡니다. 맡은 사람이 없는 바람(\"누가 해야 하는데\")은 할 일이 아니므로 빼거나 questions에 넣습니다."
            case .questions:
                scenario == .seminar
                    ? "- questions: 줄에서 청중이 실제로 한 질문과, 답이 나왔다면 짧은 답. 강연자가 답하지 못했거나 나중에 답하겠다고 한 질문도 포함. 아무도 묻지 않았다면 비워 두고, 질문을 지어내지 마세요."
                    : "- questions: 열려 있는 일. 물었지만 답이 없는 것, 다음으로 미룬 것, 승인이나 정보를 기다리는 것."
            }
        },
        leaveEmpty: { "다음 항목은 비워 두세요: " + $0.map(\.rawValue).joined(separator: ", ") + "." },
        rulesTitle: "규칙:",
        rules: [
            "1. 줄에 있는 내용만 쓰세요. 이름, 날짜, 숫자, 결정을 지어내지 마세요. 맞는 내용이 없으면 그 항목은 비워 두세요.",
            "2. lines = 그 내용이 나온 한 줄에서 세 줄의 번호. 세 줄을 넘겨 적지 마세요.",
            "3. 항목은 서기가 쓰듯 내용 자체를 담은 짧은 평서문 한 문장으로 쓰세요(예: \"마감이 금요일로 바뀌었다\"). 어떻게 알았는지는 쓰지 않습니다.",
            "4. 한 가지 내용은 한 목록에만 넣으세요. 아직 정해지지 않은 일은 결정이 아니라 questions입니다. 여러 사람이 각자 맡은 일은 각각 항목으로 씁니다.",
            "5. 이름, 숫자, 요일, 날짜는 말한 그대로 옮기세요.",
        ],
        exampleTitle: "답의 모양을 보여 주는 예시입니다. 전혀 다른 내용이므로 예시의 단어, 이름, 날짜를 절대 가져다 쓰지 마세요.",
        notesLabel: "정리:",
        meetingExample: Sample(
            transcript: [
                "기록:",
                "[1] 00:00:05 워크숍 장소를 어디로 할까요?",
                "[2] 00:00:12 호수 근처 펜션이 있고, 시내 호텔도 있습니다.",
                "[3] 00:00:20 호텔이 더 싸니까 호텔로 예약하죠.",
                "[4] 00:00:28 좋아요. 하윤 씨, 초대장은 목요일까지 보내 주세요.",
                "[5] 00:00:33 네, 제가 보내겠습니다.",
                "[6] 00:00:36 저는 내일 회의실을 잡아 두겠습니다.",
                "[7] 00:00:40 케이터링이 아직 필요한지는 모르겠어요.",
            ],
            answer: [
                .summary: "summary: 워크숍 장소를 정하고 초대장 발송을 맡겼다.",
                .decisions: "decisions: {text: \"워크숍 장소는 시내 호텔로 예약한다\", lines: [3]}",
                .actions: "actions: {text: \"초대장 발송\", owner: \"하윤\", due: \"목요일\", lines: [4, 5]} {text: \"회의실 예약\", owner: \"\", due: \"내일\", lines: [6]}",
                .questions: "questions: {text: \"케이터링이 아직 필요한지\", lines: [7]}",
                .keyPoints: "keyPoints: {text: \"호텔이 펜션보다 비용이 적다\", lines: [2, 3]}",
            ]
        ),
        talkExample: Sample(
            transcript: [
                "기록:",
                "[1] 00:00:04 꿀벌은 우리가 못 보는 자외선을 봅니다.",
                "[2] 00:00:11 많은 꽃에는 자외선에서만 보이는 무늬가 있어서 활주로 역할을 합니다.",
                "[3] 00:00:19 질문 있나요? 꿀벌도 빨간색을 보나요? 거의 못 봅니다, 검게 보입니다.",
            ],
            answer: [
                .summary: "summary: 꿀벌이 꽃을 어떻게 보는지 설명한 강연이다.",
                .keyPoints: "keyPoints: {text: \"꿀벌은 자외선을 본다\", lines: [1]} {text: \"자외선에서만 보이는 꽃무늬가 꿀벌을 안내한다\", lines: [2]}",
                .questions: "questions: {text: \"꿀벌도 빨간색을 보나요? 거의 못 보고 검게 보인다\", lines: [3]}",
            ]
        )
    )

    // MARK: Japanese

    private static let japanese = Wording(
        role: { scenario in
            switch scenario {
            case .conversation: "あなたは二人の会話を、そのうちの一人のために短くまとめます。必ず日本語だけで書いてください。"
            case .meeting: "あなたはすべての発言を追えなかった人のために議事録を書きます。必ず日本語だけで書いてください。"
            case .seminar: "あなたは聞くだけだった人のために講演のノートを書きます。必ず日本語だけで書いてください。"
            }
        },
        input: "入力は音声認識で作った書き起こしです。各行は「[番号] 時刻 内容」です。言いよどみ、つなぎ言葉、繰り返しは無視してください。",
        fieldsTitle: "次の項目を埋めてください：",
        field: { section, scenario in
            switch section {
            case .summary: "- summary: この部分が何についてだったかを、完結した一、二文で。キーワードの羅列は不可。"
            case .keyPoints:
                scenario == .seminar
                    ? "- keyPoints: 講演者が述べた主な主張、説明、数字、例を、一項目に一つずつ。"
                    : "- keyPoints: 覚えておくべき内容（計画、約束、事実）を、一項目に一つずつ。"
            case .decisions: "- decisions: 人々がはっきり決めたことだけ（「〜にしましょう」「そう決定します」、合意後の「〜はしないことに」）。決定ではないもの：選択肢や提案、意見、質問、検討中や承認待ちのこと、そして誰かに任せたこと（それはやること）。"
            case .actions: "- actions: このあと誰かがやること。本人が引き受けた（「私が送ります」）か、頼まれて承諾したもの（「○○さん、金曜までにお願いします」に「はい」と答えれば○○さんのやること）。text = やることだけを書き、人や日付は text に繰り返さない。owner = 名前が言われたときだけその名前、なければ空。due = 言われた日付や曜日をそのまま、なければ空。担当者のいない願望（「誰かがやるべき」）はやることではないので、省くか questions に入れます。"
            case .questions:
                scenario == .seminar
                    ? "- questions: 行の中で聴衆が実際にした質問と、答えがあればその短い答え。講演者が答えられなかった質問や後で答えると言った質問も含む。誰も質問しなければ空にし、質問を作らない。"
                    : "- questions: 未解決のこと。聞かれたが答えのないもの、次回に回したもの、承認や情報を待っているもの。"
            }
        },
        leaveEmpty: { "次の項目は空にしてください：" + $0.map(\.rawValue).joined(separator: "、") + "。" },
        rulesTitle: "規則：",
        rules: [
            "1. 行にある内容だけを書く。名前、日付、数字、決定を作り出さない。合う内容がなければ、その項目は空にする。",
            "2. lines = その内容が言われた一行から三行の番号。四行以上は書かない。",
            "3. 各項目は、書記が書くように内容そのものを述べる短い平叙文一文にする（例：「締め切りが金曜日に変わった」）。どうやって知ったかは書かない。",
            "4. 一つの内容は一つの一覧にだけ入れる。まだ決まっていないことは決定ではなく questions。複数の人がそれぞれ引き受けたことは、それぞれ別の項目にする。",
            "5. 名前、数字、曜日、日付は話されたとおりに写す。",
        ],
        exampleTitle: "答えの形を示す例です。まったく別の内容なので、例の言葉、名前、日付を決して使わないでください。",
        notesLabel: "まとめ：",
        meetingExample: Sample(
            transcript: [
                "書き起こし：",
                "[1] 00:00:05 懇親会の会場はどこにしましょうか。",
                "[2] 00:00:12 湖畔のロッジと、市内のホテルがあります。",
                "[3] 00:00:20 ホテルのほうが安いので、ホテルを予約しましょう。",
                "[4] 00:00:28 いいですね。さくらさん、招待状を木曜日までに送ってください。",
                "[5] 00:00:33 はい、私が送ります。",
                "[6] 00:00:36 私は明日、部屋を押さえておきます。",
                "[7] 00:00:40 ケータリングがまだ必要かは分かりません。",
            ],
            answer: [
                .summary: "summary: 懇親会の会場を決め、招待状の送付を依頼した。",
                .decisions: "decisions: {text: \"懇親会の会場は市内のホテルを予約する\", lines: [3]}",
                .actions: "actions: {text: \"招待状を送る\", owner: \"さくら\", due: \"木曜日\", lines: [4, 5]} {text: \"部屋を押さえる\", owner: \"\", due: \"明日\", lines: [6]}",
                .questions: "questions: {text: \"ケータリングがまだ必要か\", lines: [7]}",
                .keyPoints: "keyPoints: {text: \"ホテルはロッジより費用が安い\", lines: [2, 3]}",
            ]
        ),
        talkExample: Sample(
            transcript: [
                "書き起こし：",
                "[1] 00:00:04 ミツバチは人間には見えない紫外線を見ています。",
                "[2] 00:00:11 多くの花には紫外線でだけ見える模様があり、滑走路の役目をします。",
                "[3] 00:00:19 質問はありますか。ミツバチは赤が見えますか。ほとんど見えず、黒く見えます。",
            ],
            answer: [
                .summary: "summary: ミツバチが花をどう見ているかを説明する講演だった。",
                .keyPoints: "keyPoints: {text: \"ミツバチは紫外線を見る\", lines: [1]} {text: \"紫外線でだけ見える花の模様がミツバチを導く\", lines: [2]}",
                .questions: "questions: {text: \"ミツバチは赤が見えるか。ほとんど見えず黒く見える\", lines: [3]}",
            ]
        )
    )

    // MARK: Chinese

    private static let chinese = Wording(
        role: { scenario in
            switch scenario {
            case .conversation: "你为两个人中的一位简要整理他们的对话。必须只用简体中文书写。"
            case .meeting: "你为没能跟上每一句话的人撰写会议纪要。必须只用简体中文书写。"
            case .seminar: "你为只是听讲的人整理讲座笔记。必须只用简体中文书写。"
            }
        },
        input: "输入是语音识别生成的文字记录。每行格式为“[编号] 时间 内容”。忽略口吃、口头禅和重复的词。",
        fieldsTitle: "请填写以下项目：",
        field: { section, scenario in
            switch section {
            case .summary: "- summary：用完整的一两句话说明这一部分讲了什么，不要罗列关键词。"
            case .keyPoints:
                scenario == .seminar
                    ? "- keyPoints：讲者提出的主要观点、解释、数字和例子，每条一项。"
                    : "- keyPoints：值得记住的内容（计划、约定、事实），每条一项。"
            case .decisions: "- decisions：只写大家明确敲定的事（“就这么定”“那就选B”，以及达成一致后的“不做X”）。不算决定的：备选方案或提议、意见、提问、仍在审核或等待批准的事，以及交给某人去做的事（那是待办）。"
            case .actions: "- actions：之后有人要做的事，因为他本人承诺（“我来发”）或被请求并答应（“小王，请周五前完成”得到“好”的回答，就是小王的待办）。text = 只写要做的事，不要在 text 里重复人和日期。owner = 只有说出名字时才写名字，否则留空。due = 原样写出所说的日期或星期，没说就留空。没有负责人的愿望（“应该有人去做”）不是待办，省略或放进 questions。"
            case .questions:
                scenario == .seminar
                    ? "- questions：行里听众真正提出的问题，如有回答则附上简短回答；讲者答不上来或答应稍后回答的问题也要写。如果没人提问就留空，不要编造问题。"
                    : "- questions：尚未解决的事：问了没有答案的、推迟到下次的、等待批准或信息的。"
            }
        },
        leaveEmpty: { "以下项目请留空：" + $0.map(\.rawValue).joined(separator: "、") + "。" },
        rulesTitle: "规则：",
        rules: [
            "1. 只写行里有的内容。不要编造名字、日期、数字或决定。没有合适内容的项目就留空。",
            "2. lines = 说到该内容的一到三行的编号，不要引用超过三行。",
            "3. 每项像书记员那样写成陈述内容本身的简短一句话（例如“截止日期改到了周五”），不要说明你是怎么知道的。",
            "4. 一条内容只放进一个列表。尚未确定的事是 questions，不是决定。几个人各自承担的事要分别写成各自的条目。",
            "5. 名字、数字、星期和日期照原话写。",
        ],
        exampleTitle: "下面是答案形式的示例。内容与本次完全无关，绝不要使用示例中的词语、名字或日期。",
        notesLabel: "整理：",
        meetingExample: Sample(
            transcript: [
                "记录：",
                "[1] 00:00:05 联谊会的场地选在哪里？",
                "[2] 00:00:12 一个是湖边的木屋，一个是市区的酒店。",
                "[3] 00:00:20 酒店更便宜，那就订酒店吧。",
                "[4] 00:00:28 好。小雅，请在周四前把请柬发出去。",
                "[5] 00:00:33 好的，我来发。",
                "[6] 00:00:36 我明天去预订会议室。",
                "[7] 00:00:40 还需不需要餐饮服务，我还不确定。",
            ],
            answer: [
                .summary: "summary：确定了联谊会的场地，并安排发送请柬。",
                .decisions: "decisions: {text: \"联谊会订市区的酒店\", lines: [3]}",
                .actions: "actions: {text: \"发送请柬\", owner: \"小雅\", due: \"周四\", lines: [4, 5]} {text: \"预订会议室\", owner: \"\", due: \"明天\", lines: [6]}",
                .questions: "questions: {text: \"是否还需要餐饮服务\", lines: [7]}",
                .keyPoints: "keyPoints: {text: \"酒店比木屋便宜\", lines: [2, 3]}",
            ]
        ),
        talkExample: Sample(
            transcript: [
                "记录：",
                "[1] 00:00:04 蜜蜂能看到人类看不到的紫外线。",
                "[2] 00:00:11 许多花朵有只在紫外线下可见的花纹，起到跑道的作用。",
                "[3] 00:00:19 有问题吗？蜜蜂能看到红色吗？基本看不到，红色在它们眼里是黑的。",
            ],
            answer: [
                .summary: "summary：讲座解释了蜜蜂如何看花。",
                .keyPoints: "keyPoints: {text: \"蜜蜂能看到紫外线\", lines: [1]} {text: \"只在紫外线下可见的花纹为蜜蜂引路\", lines: [2]}",
                .questions: "questions: {text: \"蜜蜂能看到红色吗？基本看不到，红色呈黑色\", lines: [3]}",
            ]
        )
    )
}
