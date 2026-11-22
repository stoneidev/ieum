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

    @Test func koreanOneSyllableMisspellingIsFixedTowardHangulWhenOnlyHangulIsListed() {
        let hangulOnly = VocabularyCorrector(terms: ["쿠버네티스", "지라"])
        #expect(hangulOnly.correct("쿠버네티즈 클러스터") == "쿠버네티스 클러스터")
    }

    @Test func hangulLoanwordsRewriteToLatinVocabulary() {
        let latin = VocabularyCorrector(terms: ["Kubernetes", "Figma", "Slack", "Terraform"])
        #expect(latin.correct("쿠버네티스 클러스터를 올립니다") == "Kubernetes 클러스터를 올립니다")
        #expect(latin.correct("큐버닉스 배포") == "Kubernetes 배포")
        #expect(latin.correct("피그마 파일을 열어요") == "Figma 파일을 열어요")
        #expect(latin.correct("슬랙으로 보내 주세요") == "Slack으로 보내 주세요")
        #expect(latin.correct("테라폼 플랜") == "Terraform 플랜")
    }

    @Test func hangulAliasKeepsAParticleOnTheLatinTerm() {
        let latin = VocabularyCorrector(terms: ["Kubernetes"])
        #expect(latin.correct("쿠버네티스를 설치했습니다") == "Kubernetes를 설치했습니다")
        #expect(latin.correct("쿠버네티스에서 확인") == "Kubernetes에서 확인")
    }

    @Test func explicitHangulVocabularyLineBeatsALatinAlias() {
        // Both spellings are listed: keep Hangul when the recognizer already said the Hangul form.
        #expect(corrector.correct("쿠버네티스 클러스터") == "쿠버네티스 클러스터")
        // A listed Hangul line still blocks the Latin alias for that exact spelling; particles stay untouched.
        #expect(corrector.correct("쿠버네티스를 설치했습니다") == "쿠버네티스를 설치했습니다")
    }

    @Test func unknownHangulLoanwordsNeedTheirOwnLine() {
        let latin = VocabularyCorrector(terms: ["Siobhan"])
        let text = "시오반이 발표합니다"
        #expect(latin.correct(text) == text)
    }

    @Test func hangulAliasTableCoversResearchMishearings() {
        #expect(VocabularyHangul.aliases(forLatin: "Kubernetes").contains("큐버닉스"))
        #expect(VocabularyHangul.aliases(forLatin: "Figma").contains("피로"))
        #expect(VocabularyHangul.aliases(forLatin: "쿠버네티스").isEmpty)
        #expect(VocabularyHangul.peelingParticle(from: "쿠버네티스를").stem == "쿠버네티스")
        #expect(VocabularyHangul.peelingParticle(from: "쿠버네티스를").particle == "를")
        #expect(VocabularyHangul.peelingParticle(from: "Kubernetes").particle.isEmpty)
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
