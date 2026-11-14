import CaptionCore
import Foundation

/// Nobody fills in a vocabulary list on a hunch. These ask at the moment it is obviously useful: right after a meeting in which
/// the same names came up, with the words already found, and each answer is one tap.
extension AppModel {
    /// After a meeting: look for names and product words in what was said and offer them.
    func suggestVocabulary() {
        let sentences = finalizedLines.filter { $0.session == sessionIndex }.map(\.text)
        vocabularySuggestions = VocabularySuggester.suggestions(from: sentences, existing: vocabulary)
        vocabularyAdded = 0
        vocabularyCardOpen = !vocabularySuggestions.isEmpty
    }

    func addSuggestedTerm(_ term: String) {
        guard vocabularySuggestions.contains(term) else { return }
        setVocabulary(vocabulary + [term])
        vocabularySuggestions.removeAll { $0 == term }
        vocabularyAdded += 1
    }

    func addAllSuggestedTerms() {
        let terms = vocabularySuggestions
        setVocabulary(vocabulary + terms)
        vocabularyAdded += terms.count
        vocabularySuggestions = []
    }

    /// "Not now": the card goes away; the words stay offered in Settings > Vocabulary.
    func dismissVocabularyCard() {
        vocabularyCardOpen = false
        vocabularyAdded = 0
    }

    func dismissVocabularyTip() {
        vocabularyTipDismissed = true
        Preferences.vocabularyTipDismissed = true
    }

    /// The tip before the first meeting: only while the list is empty and the person has not waved it away.
    var showsVocabularyTip: Bool { vocabulary.isEmpty && !vocabularyTipDismissed }

    func openVocabularySettings() {
        Preferences.settingsTab = 2
        openSettings()
    }
}
