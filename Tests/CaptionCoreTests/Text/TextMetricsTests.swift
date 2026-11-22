import Foundation
import Testing

@testable import CaptionCore

@Suite("Text metrics")
struct TextMetricsTests {
    @Test func identicalTextHasNoErrors() {
        #expect(TextMetrics.wordErrorRate(reference: "Open the shared spreadsheet.", hypothesis: "open the SHARED spreadsheet") == 0)
    }

    @Test func oneSubstitutionInFourWords() {
        #expect(TextMetrics.wordErrorRate(reference: "open the shared spreadsheet", hypothesis: "open the shared spread sheet") == 0.5)
        #expect(TextMetrics.wordErrorRate(reference: "open the shared spreadsheet", hypothesis: "open the shared worksheet") == 0.25)
    }

    @Test func deletionsAndInsertionsCount() {
        #expect(TextMetrics.wordErrorRate(reference: "a b c d", hypothesis: "a c d") == 0.25)
        #expect(TextMetrics.wordErrorRate(reference: "a b", hypothesis: "a b c d") == 1)
    }

    @Test func emptyReferenceIsHandled() {
        #expect(TextMetrics.wordErrorRate(reference: "", hypothesis: "") == 0)
        #expect(TextMetrics.wordErrorRate(reference: "", hypothesis: "x") == 1)
    }

    @Test func koreanCharacterErrorRateIgnoresSpacingAndPunctuation() {
        #expect(TextMetrics.characterErrorRate(reference: "공유된 스프레드시트를 열어 주세요.", hypothesis: "공유된스프레드시트를 열어주세요") == 0)
        #expect(TextMetrics.characterErrorRate(reference: "열어 주세요", hypothesis: "열어 주세오") == 0.2)
    }

    @Test func sequenceSimilarityIsOneForEqualSequences() {
        #expect(TextMetrics.sequenceSimilarity(["a", "b", "c"], ["a", "b", "c"]) == 1)
        #expect(TextMetrics.sequenceSimilarity([Character](), [Character]()) == 1)
    }

    @Test func sequenceSimilarityFallsWithEdits() {
        #expect(TextMetrics.sequenceSimilarity(["a", "b"], ["a", "c"]) == 0.5)
        #expect(TextMetrics.sequenceSimilarity(["a"], ["a", "b"]) == 0.5)
        #expect(TextMetrics.sequenceSimilarity(["x"], ["y"]) == 0)
    }
}
