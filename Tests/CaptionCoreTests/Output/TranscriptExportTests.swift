import Foundation
import Testing

@testable import CaptionCore

@Suite("Transcript export")
struct TranscriptExportTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let sample = """
    # Transcript (conversation) started 2026-11-12 10:00:00
    [10:00:05] [EN] Can we ship the beta on Thursday?
    [10:00:05] [KO] → 목요일에 베타를 출시할 수 있을까요?
    [10:00:12] [KO] QA가 끝나면 가능합니다.
    [10:00:12] [EN] → It's possible once QA is done.
    [10:01:30] [EN] Great.
    """

    @Test func readsSentencesTranslationsAndTimes() {
        let script = ScriptParser.parse(sample, timeZone: utc)
        #expect(script.entries.count == 3)
        #expect(script.entries[0] == ScriptEntry(offset: 5, language: "en", text: "Can we ship the beta on Thursday?", translation: "목요일에 베타를 출시할 수 있을까요?"))
        #expect(script.entries[1].offset == 12 && script.entries[1].translation == "It's possible once QA is done.")
        #expect(script.entries[2].offset == 90 && script.entries[2].translation == nil)
        #expect(script.startedAt != nil)
    }

    @Test func plainTranscriptsWithoutTagsParse() {
        let script = ScriptParser.parse("# Transcript (en-US) started 2026-11-12 09:30:00\n[09:30:02] Hello there\n[09:30:02] → 안녕하세요\n", timeZone: utc)
        #expect(script.entries == [ScriptEntry(offset: 2, language: nil, text: "Hello there", translation: "안녕하세요")])
    }

    @Test func aMeetingPastMidnightKeepsCounting() {
        let script = ScriptParser.parse("# Transcript (en-US) started 2026-11-12 23:59:00\n[23:59:30] Before\n[00:00:30] After\n", timeZone: utc)
        #expect(script.entries.map(\.offset) == [30, 90])
    }

    @Test func srtHasNumberedCuesWithCommaMilliseconds() {
        let srt = TranscriptExport.render(ScriptParser.parse(sample, timeZone: utc), format: .srt)
        #expect(srt.hasPrefix("1\n00:00:05,000 --> 00:00:"))
        #expect(srt.contains("Can we ship the beta on Thursday?\n목요일에 베타를 출시할 수 있을까요?\n"))
        #expect(srt.contains("\n3\n00:01:30,000 --> "))
    }

    @Test func vttStartsWithTheHeaderAndUsesDots() {
        let vtt = TranscriptExport.render(ScriptParser.parse(sample, timeZone: utc), format: .vtt)
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:05.000 --> "))
        #expect(!vtt.contains(",000"))
    }

    @Test func aCueNeverRunsIntoTheNextOne() {
        let script = ScriptParser.parse("# Transcript (en-US) started 2026-11-12 09:00:00\n[09:00:00] This is a long sentence that would take a while to read on screen.\n[09:00:02] Next\n", timeZone: utc)
        let srt = TranscriptExport.render(script, format: .srt)
        #expect(srt.contains("00:00:00,000 --> 00:00:01,900"))
    }

    @Test func contentChoiceSelectsOriginalOrTranslation() {
        let script = ScriptParser.parse(sample, timeZone: utc)
        let original = TranscriptExport.render(script, format: .srt, content: .original)
        let translated = TranscriptExport.render(script, format: .srt, content: .translation)
        #expect(!original.contains("목요일") && original.contains("Can we ship"))
        #expect(translated.contains("목요일") && !translated.contains("Can we ship"))
    }

    @Test func markdownListsEverySentence() {
        let md = TranscriptExport.render(ScriptParser.parse(sample, timeZone: utc), format: .markdown, title: "Weekly sync", timeZone: utc)
        #expect(md.hasPrefix("# Weekly sync\n\nStarted 2026-11-12 10:00"))
        #expect(md.contains("**00:00:05** `EN` Can we ship the beta on Thursday?  \n> 목요일에 베타를 출시할 수 있을까요?"))
    }

    @Test func fileExtensionsMatchTheFormat() {
        #expect(TranscriptExport.Format.allCases.map(\.fileExtension) == ["srt", "vtt", "md"])
    }

    @Test func timecodesRoundToMilliseconds() {
        #expect(TranscriptExport.timecode(3725.5, comma: true) == "01:02:05,500")
        #expect(TranscriptExport.timecode(-3, comma: false) == "00:00:00.000")
    }
}
