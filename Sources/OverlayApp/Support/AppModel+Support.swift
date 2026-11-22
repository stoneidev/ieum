import AppKit
import CaptionCore
import Foundation

/// The friendly coffee ask: counted on this Mac only, shown after a finished meeting, easy to answer and easy to turn off.
enum Support {
    static let coffeeURL = URL(string: "https://buymeacoffee.com/stoni")!
}

extension AppModel {
    /// Called when the person ended a meeting. A meeting with a few sentences counts; the ask may be due.
    func noteMeetingFinished() {
        let sentences = finalizedLines.filter { $0.session == sessionIndex }.count
        var state = support
        let stage = state.finishedMeeting(sentences: sentences)
        save(state)
        if let stage { coffeeStage = stage }
        suggestVocabulary()
    }

    private func save(_ state: SupportState) {
        support = state
        Preferences.support = state
    }

    /// "Not now": the ask comes back at the next milestone.
    func postponeCoffee() { coffeeStage = nil }

    /// "No thanks": never again.
    func declineCoffee() {
        var state = support
        state.declined()
        save(state)
        coffeeStage = nil
    }

    /// Opens the page. The person decided; they are thanked and not asked again.
    func openCoffeePage() {
        NSWorkspace.shared.open(Support.coffeeURL)
        var state = support
        state.supported()
        save(state)
        coffeeStage = nil
        coffeeThanks = true
    }

    func dismissThanks() { coffeeThanks = false }

    var coffeeReminders: Bool { support.status == .active }

    func setCoffeeReminders(_ on: Bool) {
        var state = support
        if on { state.reminded() } else { state.declined() }
        save(state)
        if !on { coffeeStage = nil }
    }

    /// Opened from a menu: no counting, no asking, just the page.
    func openCoffeePageFromMenu() {
        NSWorkspace.shared.open(Support.coffeeURL)
    }

    @MainActor
    var coffeeTitle: String {
        let n = support.meetings
        switch coffeeStage ?? 0 {
        case 0: return tr("That was meeting number \(n) ☕", "벌써 \(n)번째 회의였어요 ☕")
        case 1: return tr("Meeting number \(n)! You are a regular now", "\(n)번째 회의! 이제 단골이시네요")
        default: return tr("\(n) meetings together. That is practically a team", "\(n)번의 회의를 함께했어요. 이쯤 되면 한 팀이에요")
        }
    }

    @MainActor
    var coffeeBody: String {
        let s = support.sentences
        switch coffeeStage ?? 0 {
        case 0: return tr("Ieum has captioned \(s) sentences for you so far. If it earned its keep, a coffee keeps the captions coming. (It runs on caffeine. Mostly mine.)",
                          "지금까지 \(s)문장을 받아 적었어요. 쓸 만하셨다면 커피 한 잔 어떠세요? 자막은 카페인으로 돌아갑니다. 대부분 제 카페인이에요.")
        case 1: return tr("\(s) sentences and counting. There is no loyalty discount, but a coffee is always welcome.",
                          "\(s)문장째 같이 달리는 중이에요. 단골 할인은 없지만 커피 한 잔은 언제나 환영입니다.")
        default: return tr("\(s) sentences together. This is the last time I will ask: a coffee keeps Ieum going.",
                           "\(s)문장을 함께했네요. 부탁은 이번이 마지막이에요. 커피 한 잔이면 이음이 오래 갑니다.")
        }
    }
}
