import Foundation
import Testing

@testable import CaptionCore

@Suite("Vocabulary corrector")
struct VocabularyCorrectorTests {
    private let corrector = VocabularyCorrector(terms: ["Kubernetes", "Terraform", "Jira", "Figma", "Siobhan", "OKR", "쿠버네티스", "Visual Studio"])

    @Test func repairsASplitMisheardTerm() {
        #expect(corrector.correct("R. Q. Bernates cluster on Azure") == "Kubernetes cluster on Azure")
    }

    @Test func repairsOneLetterMisspelling() {
        #expect(corrector.correct("open the Jera backlog.") == "open the Jira backlog.")
    }

    @Test func fixesCapitalization() {
        #expect(corrector.correct("the figma handoff and terraform plans") == "the Figma handoff and Terraform plans")
    }

    @Test func keepsSurroundingPunctuation() {
        #expect(corrector.correct("We use Jera, then (figma).") == "We use Jira, then (Figma).")
    }

    @Test func leavesUnrelatedTextAlone() {
        let text = "The quick brown fox jumps over the lazy dog, show on the screen."
        #expect(corrector.correct(text) == text)
    }

    @Test func shortTermsMustMatchExactlyNotFuzzily() {
        // "OK our" sounds a bit like OKR but fuzzy matching three-letter terms would rewrite ordinary words.
        #expect(corrector.correct("OK our review") == "OK our review")
        #expect(corrector.correct("the okr review") == "the OKR review")
    }

    @Test func alreadyCorrectTermsAreUntouched() {
        let text = "Siobhan will present the Kubernetes plan."
        #expect(corrector.correct(text) == text)
    }

    @Test func multiWordTermsFixCase() {
        #expect(corrector.correct("open visual studio now") == "open Visual Studio now")
    }

    @Test func koreanSplitTermIsJoined() {
        #expect(corrector.correct("쿠 버네티스 클러스터") == "쿠버네티스 클러스터")
    }

    @Test func koreanParticlesAreNotStripped() {
        let text = "쿠버네티스를 설치했습니다"
        #expect(corrector.correct(text) == text)
    }

    @Test func koreanOneSyllableMisspellingIsFixed() {
        #expect(corrector.correct("쿠버네티즈 클러스터") == "쿠버네티스 클러스터")
    }

    /// A tiny stand-in for the system dictionary.
    private static let dictionary: Set<String> = ["code", "mode", "note", "just", "must", "stack", "black", "locker", "cube", "the", "and", "is", "a"]
    private let careful = VocabularyCorrector(
        terms: ["Node", "Rust", "Slack", "Docker", "Kube", "Jira"],
        isKnownWord: { VocabularyCorrectorTests.dictionary.contains($0.lowercased()) }
    )

    @Test func ordinaryWordsNearAShortTermAreNeverRewritten() {
        let text = "the code and mode note just must stack black locker is a cube"
        #expect(careful.correct(text) == text)
    }

    @Test func aMisspellingThatIsNotAWordIsStillFixed() {
        #expect(careful.correct("open the Jera board") == "open the Jira board")
        #expect(careful.correct("deploy with Dokker now") == "deploy with Docker now")
    }

    @Test func exactMatchesIgnoreTheDictionary() {
        #expect(careful.correct("the node is down") == "the Node is down")
        #expect(careful.correct("use slack and rust") == "use Slack and Rust")
    }

    @Test func theSystemDictionaryKnowsOrdinaryWords() {
        for word in ["code", "mode", "stack", "locker"] { #expect(WordList.isKnownEnglishWord(word)) }
        for word in ["Jera", "Kubernetes", "Siobhan"] { #expect(!WordList.isKnownEnglishWord(word)) }
    }

    @Test func emptyVocabularyChangesNothing() {
        let empty = VocabularyCorrector(terms: [" ", ""])
        #expect(empty.isEmpty)
        #expect(empty.correct("anything at all") == "anything at all")
    }

    @Test func duplicateAndSingleLetterTermsAreIgnored() {
        let c = VocabularyCorrector(terms: ["Jira", "jira", "A"])
        #expect(c.correct("a jera ticket") == "a Jira ticket")
    }

    @Test func streamAppliesToPartialsAndFinals() async throws {
        let (stream, continuation) = AsyncThrowingStream<TranscriptionEvent, Error>.makeStream()
        continuation.yield(TranscriptionEvent(text: "the figma", isFinal: false, locale: "en-US"))
        continuation.yield(TranscriptionEvent(text: "the figma file", isFinal: true, locale: "en-US"))
        continuation.finish()
        var texts: [String] = []
        for try await event in corrector.apply(to: stream) { texts.append(event.text) }
        #expect(texts == ["the Figma", "the Figma file"])
    }

    @Test func streamPassesThroughWhenThereIsNoVocabulary() async throws {
        let (stream, continuation) = AsyncThrowingStream<TranscriptionEvent, Error>.makeStream()
        continuation.yield(TranscriptionEvent(text: "unchanged", isFinal: true, locale: "en-US"))
        continuation.finish()
        var texts: [String] = []
        for try await event in VocabularyCorrector(terms: []).apply(to: stream) { texts.append(event.text) }
        #expect(texts == ["unchanged"])
    }
}
