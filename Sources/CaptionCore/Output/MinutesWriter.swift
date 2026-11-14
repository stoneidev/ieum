import Foundation
import FoundationModels

/// Writes the notes of a meeting with the on-device language model: reads the transcript part by part, with the instructions
/// of the situation, and hands what the model wrote through the same clean-up every time. Nothing leaves the Mac.
@available(macOS 26.0, *)
public enum MinutesWriter {
    /// The most characters of one sentence that are read; a single longer line is cut here when it does not fit the model's window.
    private static let longestLine = 1_200

    /// Reads the transcript part by part and returns the notes of `scenario`. `progress` receives (parts done, parts in all).
    public static func generate(
        entries: [ScriptEntry],
        language: SpokenLanguage,
        scenario: Scenario,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> MeetingMinutes {
        let chunks = MinutesSource.chunks(entries)
        let template = scenario.minutes
        let instructions = MinutesPrompt.instructions(for: template, scenario: scenario, language: language)
        var all = MeetingMinutes(parts: [], decisions: [], actions: [])
        await progress(0, chunks.count)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let read = try await read(chunk, of: entries, instructions: instructions)
            all.unread += read.skipped
            for piece in read.pieces {
                all.parts.append(piece.part)
                all.decisions += piece.decisions
                all.actions += piece.actions
                all.keyPoints += piece.keyPoints
                all.questions += piece.questions
            }
            await progress(index + 1, chunks.count)
        }
        try Task.checkCancellation()
        return all.validated(entryCount: entries.count, template: template).grounded(in: entries)
    }

    private struct Piece {
        var part: MeetingMinutes.Part
        var decisions: [MeetingMinutes.Point]
        var actions: [MeetingMinutes.Point]
        var keyPoints: [MeetingMinutes.Point]
        var questions: [MeetingMinutes.Point]
    }

    /// One part of the transcript. A part that is still too long for the model is cut in half and read as two.
    private static func read(_ chunk: MinutesSource.Chunk, of entries: [ScriptEntry], instructions: String) async throws -> (pieces: [Piece], skipped: [Int]) {
        // The notes only rewrite what the people said, so the transformation guardrails apply: the default ones refuse ordinary
        // talks about privacy, failures or money.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
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
            return ([Piece(part: .init(lines: chunk.lines, summary: draft.summary), decisions: points(draft.decisions), actions: points(draft.actions),
                           keyPoints: points(draft.keyPoints), questions: points(draft.questions))], [])
        } catch let error as LanguageModelSession.GenerationError {
            // Too long, or the model declined this stretch: read it as two halves. One line it still declines is left out
            // rather than failing the notes of a whole meeting.
            switch error {
            case .exceededContextWindowSize, .guardrailViolation, .refusal:
                guard chunk.end - chunk.start > 1 else {
                    // One line. A line too long for the window (recognizers can produce a page without a full stop) is read cut short,
                    // once; a line the model declines is reported as unread, never silently left out.
                    if case .exceededContextWindowSize = error, entries[chunk.start].text.count > Self.longestLine {
                        var shorter = entries
                        shorter[chunk.start].text = String(entries[chunk.start].text.prefix(Self.longestLine))
                        return try await read(chunk, of: shorter, instructions: instructions)
                    }
                    return ([], [chunk.start + 1])
                }
                let middle = chunk.start + (chunk.end - chunk.start) / 2
                let left = try await read(.init(start: chunk.start, end: middle), of: entries, instructions: instructions)
                try Task.checkCancellation()
                let right = try await read(.init(start: middle, end: chunk.end), of: entries, instructions: instructions)
                return (left.pieces + right.pieces, left.skipped + right.skipped)
            default:
                throw error
            }
        }
    }

    /// Every situation is read into the same shape; the instructions say which parts to fill and the notes show only those.
    @Generable
    struct Draft {
        @Generable
        struct Entry {
            @Guide(description: "One short sentence about the point itself. For a task: only the action, without repeating the person or the date")
            var text: String
            @Guide(description: "The numbers (in square brackets at the start of the lines) of the one to three lines where this is said")
            var lines: [Int]
            @Guide(description: "For a task: the name of the person who will do it, exactly as said in the lines. Empty when no name is said. Never guess")
            var owner: String
            @Guide(description: "For a task: the day or date exactly as said in the lines. Empty when none is said. Never guess")
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
