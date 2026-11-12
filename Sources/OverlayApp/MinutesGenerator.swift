import CaptionCore
import FoundationModels
import Foundation

/// Writes a draft of meeting minutes with the on-device language model (Apple Intelligence). Nothing leaves the Mac.
enum MinutesGenerator {
    enum Status {
        case ready
        /// This Mac cannot offer minutes at all (macOS before 26, or no Apple Intelligence): the feature is not shown.
        case notOffered
        /// This Mac can, but not right now: shown greyed out with the reason.
        case unavailable(String)
    }

    @MainActor
    static func status(for language: SpokenLanguage) -> Status {
        guard #available(macOS 26.0, *) else { return .notOffered }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return .notOffered
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(tr("Turn on Apple Intelligence in System Settings.", "시스템 설정에서 Apple Intelligence를 켜세요."))
        case .unavailable(.modelNotReady):
            return .unavailable(tr("The language model is still downloading. Try again later.", "언어 모델을 내려받는 중입니다. 잠시 뒤에 다시 시도하세요."))
        case .unavailable:
            return .unavailable(tr("The language model is not available.", "언어 모델을 사용할 수 없습니다."))
        }
        guard model.supportsLocale(Locale(identifier: language.code)) else {
            return .unavailable(tr("Apple Intelligence does not support this language yet.", "Apple Intelligence가 아직 이 언어를 지원하지 않습니다."))
        }
        return .ready
    }

    /// Whether this Mac can ever make minutes (used to show the feature and its "What's new" page only to people who can use it).
    @MainActor
    static var isOffered: Bool {
        if case .notOffered = status(for: .english) { false } else { true }
    }

    /// Reads the transcript part by part and returns the minutes. `progress` receives (parts done, parts in all).
    @available(macOS 26.0, *)
    static func generate(
        entries: [ScriptEntry],
        language: SpokenLanguage,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> MeetingMinutes {
        let chunks = MinutesSource.chunks(entries)
        var parts: [MeetingMinutes.Part] = []
        var decisions: [MeetingMinutes.Point] = []
        var actions: [MeetingMinutes.Point] = []
        await progress(0, chunks.count)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            for piece in try await read(chunk, of: entries, language: language) {
                parts.append(piece.part)
                decisions += piece.decisions
                actions += piece.actions
            }
            await progress(index + 1, chunks.count)
        }
        try Task.checkCancellation()
        return MeetingMinutes(parts: parts, decisions: decisions, actions: actions).validated(entryCount: entries.count)
    }

    private struct Piece {
        var part: MeetingMinutes.Part
        var decisions: [MeetingMinutes.Point]
        var actions: [MeetingMinutes.Point]
    }

    /// One part of the transcript. A part that is still too long for the model is cut in half and read as two.
    @available(macOS 26.0, *)
    private static func read(_ chunk: MinutesSource.Chunk, of entries: [ScriptEntry], language: SpokenLanguage) async throws -> [Piece] {
        let session = LanguageModelSession(instructions: instructions(language))
        do {
            let response = try await session.respond(
                to: "Transcript:\n" + MinutesSource.numbered(entries, chunk),
                generating: Draft.self,
                options: GenerationOptions(temperature: 0)
            )
            let draft = response.content
            // A line the model cites from outside the part it was reading cannot be what the point is based on.
            func points(_ items: [Draft.Point]) -> [MeetingMinutes.Point] {
                items.map { .init(text: $0.text, lines: $0.lines.filter { chunk.lines.contains($0) }) }
            }
            return [Piece(part: .init(lines: chunk.lines, summary: draft.summary), decisions: points(draft.decisions), actions: points(draft.actions))]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where chunk.end - chunk.start > 1 {
            let middle = chunk.start + (chunk.end - chunk.start) / 2
            return try await read(.init(start: chunk.start, end: middle), of: entries, language: language)
                + read(.init(start: middle, end: chunk.end), of: entries, language: language)
        }
    }

    @available(macOS 26.0, *)
    @Generable
    struct Draft {
        @Generable
        struct Point {
            @Guide(description: "One short sentence. For a task: what is to be done, by whom if said, and by when, with the day or date copied exactly")
            var text: String
            @Guide(description: "The numbers in square brackets at the start of the transcript lines this is based on")
            var lines: [Int]
        }

        @Guide(description: "One or two complete sentences (not a list of keywords): what this part of the meeting was about")
        var summary: String
        @Guide(description: "Only things that were clearly agreed or announced as decided. A question, a proposal, or something still being reviewed is not a decision", .maximumCount(6))
        var decisions: [Point]
        @Guide(description: "Tasks someone promised or was asked to do. Each one keeps the person and the day or date exactly as said", .maximumCount(6))
        var actions: [Point]
    }

    /// The model writes in the language of its instructions, so they are given in the language the minutes should be in.
    private static func instructions(_ language: SpokenLanguage) -> String {
        switch language {
        case .english: "You write meeting minutes. Write only in English. Use only what the transcript says and copy dates and weekdays exactly. Never invent anything. A question or an unfinished matter is not a decision. Keep who and when for every task. Cite the line numbers."
        case .korean: "당신은 회의록 작성자입니다. 반드시 한국어로만 쓰세요. 대화록에 있는 내용만 쓰고, 날짜와 요일은 대화록에 나온 그대로 옮기세요. 없는 내용을 지어내지 마세요. 질문이나 아직 검토 중인 일은 결정이 아닙니다. 할 일에는 누가, 언제까지인지를 반드시 넣으세요. 근거가 되는 줄 번호를 적으세요."
        case .japanese: "あなたは議事録の作成者です。必ず日本語だけで書いてください。書き起こしにある内容だけを書き、日付や曜日は書き起こしのとおりに写してください。ないことを作らないでください。質問や検討中のことは決定事項ではありません。やることには、誰がいつまでにを必ず入れてください。根拠となる行番号を書いてください。"
        case .chinese: "你是会议纪要的撰写者。必须只用简体中文书写。只写文字记录里有的内容，日期和星期必须与记录完全一致。不要编造记录里没有的内容。提问或仍在审核的事项不是决定。待办事项必须写明由谁、何时完成。请写出所依据的行号。"
        }
    }
}
