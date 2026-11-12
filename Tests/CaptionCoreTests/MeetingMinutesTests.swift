import Foundation
import Testing

@testable import CaptionCore

@Suite("Meeting minutes")
struct MeetingMinutesTests {
    private func entries(_ texts: [String]) -> [ScriptEntry] {
        texts.enumerated().map { ScriptEntry(offset: Double($0.offset) * 10, text: $0.element) }
    }

    @Test func aShortTranscriptIsOnePart() {
        let chunks = MinutesSource.chunks(entries(["one", "two", "three"]))
        #expect(chunks == [MinutesSource.Chunk(start: 0, end: 3)])
        #expect(chunks[0].lines == 1...3)
    }

    @Test func aLongTranscriptIsCutIntoConsecutivePartsWithinTheBudget() {
        let sentence = String(repeating: "word ", count: 60)   // 300 characters
        let all = entries(Array(repeating: sentence, count: 30))
        let chunks = MinutesSource.chunks(all)
        #expect(chunks.count > 1)
        #expect(chunks.first?.start == 0)
        #expect(chunks.last?.end == 30)
        for (a, b) in zip(chunks, chunks.dropFirst()) { #expect(a.end == b.start) }
        for chunk in chunks { #expect(chunk.end - chunk.start <= 11) }
    }

    @Test func japaneseGetsSmallerPartsThanEnglish() {
        let japanese = entries(Array(repeating: String(repeating: "会議の内容", count: 20), count: 20))
        let english = entries(Array(repeating: String(repeating: "abcde ", count: 17), count: 20))
        #expect(MinutesSource.chunks(japanese).count > MinutesSource.chunks(english).count)
    }

    @Test func oneSentenceLongerThanTheBudgetIsAPartOfItsOwn() {
        let chunks = MinutesSource.chunks(entries(["short", String(repeating: "x", count: 5_000), "tail"]))
        #expect(chunks.map(\.start) == [0, 1, 2])
    }

    @Test func noEntriesNoParts() {
        #expect(MinutesSource.chunks([]).isEmpty)
    }

    @Test func linesAreNumberedAsInTheWholeTranscript() {
        let all = entries(["a", "b", "c"])
        let text = MinutesSource.numbered(all, MinutesSource.Chunk(start: 1, end: 3))
        #expect(text == "[2] 00:00:10 b\n[3] 00:00:20 c")
    }

    @Test func invalidLineNumbersAreDroppedAndEmptyPointsRemoved() {
        let minutes = MeetingMinutes(
            parts: [.init(lines: 1...3, summary: "  "), .init(lines: 1...3, summary: "Talked about the beta.")],
            decisions: [.init(text: "Start Monday", lines: [2, 2, 9, 0, -1]), .init(text: " ", lines: [1]), .init(text: "Start Monday", lines: [1])],
            actions: [.init(text: "Update notes", lines: [])]
        ).validated(entryCount: 3)
        #expect(minutes.parts.count == 1)
        #expect(minutes.decisions == [.init(text: "Start Monday", lines: [2])])
        #expect(minutes.actions == [.init(text: "Update notes", lines: [])])
    }

    @Test func aSummaryPastedIntoAListIsDropped() {
        let minutes = MeetingMinutes(
            parts: [.init(lines: 1...20, summary: "They talked about plans.")],
            decisions: [
                .init(text: "They talked about plans.", lines: [1]),
                .init(text: "Something about many lines", lines: Array(1...20)),
                .init(text: "Ship Monday", lines: [3]),
            ],
            actions: []
        ).validated(entryCount: 20)
        #expect(minutes.decisions == [.init(text: "Ship Monday", lines: [3])])
    }

    @Test func markdownCitesLinesAndMarksPointsWithoutASource() {
        let all = entries(["a", "b", "c"])
        let minutes = MeetingMinutes(
            parts: [.init(lines: 1...3, summary: "Beta test planning.")],
            decisions: [.init(text: "Start Monday", lines: [2])],
            actions: [.init(text: "Update notes (Wednesday)", lines: [])]
        )
        let md = MinutesMarkdown.render(minutes, entries: all, title: "Budget", language: .english)
        #expect(md.hasPrefix("# Budget\n\n> Draft made on this Mac"))
        #expect(md.contains("## Summary\n\nBeta test planning.\n"))
        #expect(md.contains("- Start Monday (lines [2] 00:00:10)\n"))
        #expect(md.contains("- Update notes (Wednesday) ⚠︎ no source line\n"))
    }

    @Test func severalPartsListTheirLineRanges() {
        let minutes = MeetingMinutes(
            parts: [.init(lines: 1...5, summary: "First."), .init(lines: 6...9, summary: "Second.")],
            decisions: [], actions: []
        )
        let md = MinutesMarkdown.render(minutes, entries: entries(Array(repeating: "x", count: 9)), title: "T", language: .korean)
        #expect(md.contains("- First. (줄 1–5)\n"))
        #expect(md.contains("- Second. (줄 6–9)\n"))
        #expect(md.contains("## 결정 사항\n\n찾지 못했습니다.\n"))
    }

    @Test func everyLanguageHasItsOwnHeadings() {
        let all = Set(SpokenLanguage.allCases.map { MinutesMarkdown.words(for: $0).summary })
        #expect(all.count == SpokenLanguage.allCases.count)
    }
}
