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

    /// Reads the transcript part by part and returns the notes of `scenario`. `progress` receives (parts done, parts in all).
    @available(macOS 26.0, *)
    static func generate(
        entries: [ScriptEntry],
        language: SpokenLanguage,
        scenario: Scenario,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> MeetingMinutes {
        let chunks = MinutesSource.chunks(entries)
        let template = scenario.minutes
        let instructions = MinutesPrompt.instructions(for: template, scenario: scenario, language: language)
        var all = MeetingMinutes(parts: [], decisions: [], actions: [])
        await progress(0, chunks.count)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            for piece in try await read(chunk, of: entries, instructions: instructions) {
                all.parts.append(piece.part)
                all.decisions += piece.decisions
                all.actions += piece.actions
                all.keyPoints += piece.keyPoints
                all.questions += piece.questions
            }
            await progress(index + 1, chunks.count)
        }
        try Task.checkCancellation()
        return all.validated(entryCount: entries.count, template: template)
    }

    private struct Piece {
        var part: MeetingMinutes.Part
        var decisions: [MeetingMinutes.Point]
        var actions: [MeetingMinutes.Point]
        var keyPoints: [MeetingMinutes.Point]
        var questions: [MeetingMinutes.Point]
    }

    /// One part of the transcript. A part that is still too long for the model is cut in half and read as two.
    @available(macOS 26.0, *)
    private static func read(_ chunk: MinutesSource.Chunk, of entries: [ScriptEntry], instructions: String) async throws -> [Piece] {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: MinutesSource.numbered(entries, chunk),
                generating: Draft.self,
                options: GenerationOptions(temperature: 0)
            )
            let draft = response.content
            // A line the model cites from outside the part it was reading cannot be what the point is based on.
            func points(_ items: [Draft.Entry]) -> [MeetingMinutes.Point] {
                items.map { .init(text: $0.text, lines: $0.lines.filter { chunk.lines.contains($0) }, owner: $0.owner, due: $0.due) }
            }
            return [Piece(part: .init(lines: chunk.lines, summary: draft.summary), decisions: points(draft.decisions), actions: points(draft.actions),
                          keyPoints: points(draft.keyPoints), questions: points(draft.questions))]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where chunk.end - chunk.start > 1 {
            let middle = chunk.start + (chunk.end - chunk.start) / 2
            return try await read(.init(start: chunk.start, end: middle), of: entries, instructions: instructions)
                + read(.init(start: middle, end: chunk.end), of: entries, instructions: instructions)
        }
    }

    /// Every situation is read into the same shape; the instructions say which parts to fill and the notes show only those.
    @available(macOS 26.0, *)
    @Generable
    struct Draft {
        @Generable
        struct Entry {
            @Guide(description: "One short sentence")
            var text: String
            @Guide(description: "The numbers in square brackets at the start of the transcript lines this is based on")
            var lines: [Int]
            @Guide(description: "For a task: the person who will do it, as named in the transcript. Empty when no person is named")
            var owner: String
            @Guide(description: "For a task: the day or date, exactly as said. Empty when none is said")
            var due: String
        }

        @Guide(description: "One or two complete sentences (not a list of keywords): what this part was about")
        var summary: String
        @Guide(description: "The most important things that were said", .maximumCount(8))
        var keyPoints: [Entry]
        @Guide(description: "Only things clearly agreed or announced as decided. A question, a proposal or something still under review is not a decision", .maximumCount(6))
        var decisions: [Entry]
        @Guide(description: "Tasks someone promised or was asked to do, with owner and due as said", .maximumCount(6))
        var actions: [Entry]
        @Guide(description: "Matters left open, or questions raised and not answered", .maximumCount(5))
        var questions: [Entry]
    }
}
