import Testing

@testable import CaptionCore

@Suite("Vocabulary suggestions")
struct VocabularySuggesterTests {
    private func suggest(_ sentences: [String], existing: [String] = [], known: Set<String> = []) -> [String] {
        VocabularySuggester.suggestions(from: sentences, existing: existing, isKnownWord: { known.contains($0) })
    }

    @Test func aNameSaidTwiceInsideSentencesIsSuggested() {
        let result = suggest(["Please ask Siobhan about it.", "Then Siobhan will send the file."])
        #expect(result == ["Siobhan"])
    }

    @Test func aWordThatOnlyOpensSentencesIsNotAName() {
        let result = suggest(["Budget is tight.", "Budget again next week.", "We will see."])
        #expect(result.isEmpty)
    }

    @Test func aWordSaidOnceIsNotSuggested() {
        #expect(suggest(["We met Siobhan yesterday."]).isEmpty)
    }

    @Test func everydayWordsAreLeftOut() {
        let result = suggest(["We use Slack daily.", "Open Slack now."], known: ["slack"])
        #expect(result.isEmpty)
    }

    @Test func aProductSpelledInMixedCaseCountsEvenOnce() {
        let result = suggest(["We moved to GraphQL last year.", "The iOS build is green."])
        #expect(Set(result) == ["GraphQL", "iOS"])
    }

    @Test func termsAlreadyInTheVocabularyAreSkippedIgnoringCase() {
        let result = suggest(["Ask Siobhan.", "Then Siobhan and GraphQL."], existing: ["siobhan", "graphql"])
        #expect(result.isEmpty)
    }

    @Test func possessivesAndPunctuationAreStripped() {
        let result = suggest(["That is Siobhan's plan, said Dana.", "Dana asked Siobhan, again."])
        #expect(result.contains("Siobhan"))
    }

    @Test func daysMonthsAndShoutedWordsAreNotNames() {
        let result = suggest(["Meet on Monday, not Friday.", "Again on Monday and Friday.", "That is GREAT news.", "GREAT again."])
        #expect(result == [], "got \(result)")
    }

    @Test func theMostRepeatedComeFirstAndTheListIsCapped() {
        var lines = ["See Alpha and Beta.", "Also Alpha and Beta.", "And Alpha."]
        lines += (1...8).map { "Ask Name\(String(repeating: "x", count: $0)) later, Name\(String(repeating: "x", count: $0)) knows." }
        let result = VocabularySuggester.suggestions(from: lines, existing: [], limit: 3, isKnownWord: { _ in false })
        #expect(result.count == 3)
        #expect(result.first == "Alpha")
    }

    @Test func koreanSentencesWithoutLatinWordsGiveNothing() {
        #expect(suggest(["다음 주에 회의를 합니다.", "다음 주에 다시 봅니다."]).isEmpty)
    }

    @Test func pluralAcronymsAreNotProducts() {
        #expect(suggest(["Our APIs and URLs and CEOs changed."]).isEmpty)
    }

    @Test func aPluralOfAListedTermIsSkipped() {
        #expect(suggest(["Our APIs changed."], existing: ["API"]).isEmpty)
    }

    @Test func aParticleStuckToAProductNameDoesNotHideIt() {
        #expect(suggest(["오늘은 GraphQL이 중요합니다.", "Kubernetes를 씁니다."]) .contains("GraphQL"))
    }

    @Test func iPhoneStyleBrandsCount() {
        #expect(suggest(["We tested on iPhone."]) == ["iPhone"])
    }

    @Test func aWordAfterAFullStopOpensASentence() {
        // "Anyway" opens the second sentence of each line; it is not a name.
        #expect(suggest(["We shipped. Anyway we moved on.", "Done. Anyway it works."]).isEmpty)
    }

    @Test func hyphenatedPhrasesAreNotProducts() {
        #expect(suggest(["Try Self-Service today."]).isEmpty)
    }
}
