import Testing

@testable import CaptionCore

@Suite("Transcript cleaner")
struct TranscriptCleanerTests {
    @Test func dropsFillerBeforeTheFirstWord() {
        #expect(TranscriptCleaner.clean(",, it turns out tradium is no exception.") == "it turns out tradium is no exception.")
        #expect(TranscriptCleaner.clean("-... will bring customers") == "will bring customers")
        #expect(TranscriptCleaner.clean(", and....") == "and…")
    }

    @Test func fillerBetweenWordsBecomesOneEllipsis() {
        #expect(TranscriptCleaner.clean("including the AWS... or NVI......... and access to......") == "including the AWS… or NVI… and access to…")
        #expect(TranscriptCleaner.clean("A A... But also, you... A,.......") == "A A… But also, you… A…")
        #expect(TranscriptCleaner.clean("bedrock,.... to.., helping") == "bedrock… to… helping")
    }

    @Test func aSentenceThatIsOnlyFillerIsEmpty() {
        #expect(TranscriptCleaner.clean(",....") == "")
        #expect(TranscriptCleaner.clean(",......................") == "")
        #expect(TranscriptCleaner.clean("... ,,") == "")
    }

    @Test func normalTextIsUntouched() {
        #expect(TranscriptCleaner.clean("Thanks, everyone. Let us begin.") == "Thanks, everyone. Let us begin.")
        #expect(TranscriptCleaner.clean("A co-op - well, yes.") == "A co-op - well, yes.")
        #expect(TranscriptCleaner.clean("다음 주 일정을 공유해 주세요.") == "다음 주 일정을 공유해 주세요.")
    }
}
