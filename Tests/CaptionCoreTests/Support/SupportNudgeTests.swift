import Foundation
import Testing

@testable import CaptionCore

@Suite("Coffee ask")
struct SupportNudgeTests {
    private func meetings(_ count: Int, in state: inout SupportState, sentences: Int = 10) -> [Int?] {
        (0..<count).map { _ in state.finishedMeeting(sentences: sentences) }
    }

    @Test func theFirstAskComesAfterTheThirdRealMeeting() {
        var state = SupportState()
        let results = meetings(3, in: &state)
        #expect(results == [nil, nil, 0])
        #expect(state.asked == 1)
    }

    @Test func aTestOrAQuickLookDoesNotCount() {
        var state = SupportState()
        for _ in 0..<10 { _ = state.finishedMeeting(sentences: 2) }
        #expect(state.meetings == 0 && state.asked == 0)
    }

    @Test func theAskReturnsAtTheNextThresholdsAndThenStops() {
        var state = SupportState()
        let results = meetings(40, in: &state)
        let asks = results.enumerated().compactMap { $0.element == nil ? nil : ($0.offset + 1, $0.element!) }
        #expect(asks.map(\.0) == [3, 12, 30])
        #expect(asks.map(\.1) == [0, 1, 2])
        #expect(!state.asksAgain)
    }

    @Test func nothingIsAskedAfterNoThanksOrAfterSupporting() {
        var declined = SupportState()
        _ = meetings(2, in: &declined)
        declined.declined()
        #expect(meetings(40, in: &declined).allSatisfy { $0 == nil })

        var supporter = SupportState()
        _ = meetings(2, in: &supporter)
        supporter.supported()
        #expect(meetings(40, in: &supporter).allSatisfy { $0 == nil })
    }

    @Test func turningTheReminderBackOnAsksAgainButNeverAfterSupporting() {
        var state = SupportState(meetings: 5, asked: 1, status: .muted)
        state.reminded()
        #expect(state.status == .active)
        var supporter = SupportState(status: .supporter)
        supporter.reminded()
        #expect(supporter.status == .supporter)
    }

    @Test func aSupporterIsNeverDowngraded() {
        var state = SupportState(meetings: 40, asked: 3, status: .supporter)
        state.declined()
        #expect(state.status == .supporter)
        state.reminded()
        #expect(state.status == .supporter)
    }

    @Test func switchingTheReminderOnAfterAllAsksWereUsedAsksOnceMore() {
        var state = SupportState(meetings: 40, asked: 3, status: .muted)
        state.reminded()
        #expect(state.asksAgain)
        #expect(state.finishedMeeting(sentences: 10) == 2)
        #expect(!state.asksAgain)
    }

    @Test func sentencesAreCountedAcrossMeetings() {
        var state = SupportState()
        _ = state.finishedMeeting(sentences: 10)
        _ = state.finishedMeeting(sentences: 25)
        #expect(state.sentences == 35)
    }

    @Test func theStateSurvivesBeingSaved() throws {
        let state = SupportState(meetings: 7, sentences: 120, asked: 1, status: .active)
        let decoded = try JSONDecoder().decode(SupportState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
