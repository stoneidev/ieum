import CoreGraphics
import Testing

@testable import CaptionCore

@Suite("Pointer avoidance")
struct PointerAvoidanceTests {
    private let bar = CGRect(x: 200, y: 56, width: 1000, height: 110)
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let zone = PointerZone()

    @Test func theWordsOfTheBarAreNear() {
        #expect(zone.isNear(pointer: CGPoint(x: 600, y: 100), bar: bar, wasNear: false))
    }

    @Test func farAwayIsNotNear() {
        #expect(!zone.isNear(pointer: CGPoint(x: 600, y: 400), bar: bar, wasNear: false))
        #expect(!zone.isNear(pointer: CGPoint(x: 50, y: 100), bar: bar, wasNear: false))
    }

    @Test func overTheControlsTheBarStaysSolid() {
        // the right 210 points hold the text size, panel and menu buttons
        #expect(!zone.isNear(pointer: CGPoint(x: 1100, y: 100), bar: bar, wasNear: false))
        #expect(!zone.isNear(pointer: CGPoint(x: 1100, y: 100), bar: bar, wasNear: true))
        #expect(zone.isNear(pointer: CGPoint(x: 950, y: 100), bar: bar, wasNear: false))
    }

    @Test func leavingNeedsMoreDistanceThanArriving() {
        let justOutside = CGPoint(x: 600, y: 56 - 15)   // 15 points under the bar
        #expect(!zone.isNear(pointer: justOutside, bar: bar, wasNear: false))
        #expect(zone.isNear(pointer: justOutside, bar: bar, wasNear: true))
        #expect(!zone.isNear(pointer: CGPoint(x: 600, y: 56 - 40), bar: bar, wasNear: true))
    }

    @Test func aBarAtTheBottomDodgesToTheTop() {
        let moved = PointerZone.opposite(of: bar, in: screen)
        #expect(moved.size == bar.size)
        #expect(moved.minX == bar.minX)
        #expect(moved.maxY == screen.maxY - 56)
    }

    @Test func aBarAtTheTopDodgesToTheBottom() {
        let top = CGRect(x: 200, y: 944 - 56 - 110, width: 1000, height: 110)
        let moved = PointerZone.opposite(of: top, in: screen)
        #expect(moved.minY == 56)
    }

    @Test func dodgingTwiceComesBack() {
        let there = PointerZone.opposite(of: bar, in: screen)
        let back = PointerZone.opposite(of: there, in: screen)
        #expect(back == bar)
    }

    @Test func theSettingHasThreeChoices() {
        #expect(PointerAvoidance.allCases == [.fade, .dodge, .off])
    }

    private let policy = FadePolicy()

    @Test func aPassingPointerDoesNotFadeTheBar() {
        #expect(policy.action(near: true, nearFor: 0.1, awayFor: 0, faded: false, solidKey: false) == .none)
    }

    @Test func aPointerThatSettlesFadesIt() {
        #expect(policy.action(near: true, nearFor: 0.5, awayFor: 0, faded: false, solidKey: false) == .fade)
    }

    @Test func leavingBringsItBackAfterAShortWhile() {
        #expect(policy.action(near: false, nearFor: 0, awayFor: 0.1, faded: true, solidKey: false) == .none)
        #expect(policy.action(near: false, nearFor: 0, awayFor: 0.5, faded: true, solidKey: false) == .unfade)
    }

    @Test func theSolidKeyKeepsTheBarUsable() {
        #expect(policy.action(near: true, nearFor: 5, awayFor: 0, faded: false, solidKey: true) == .none)
        #expect(policy.action(near: true, nearFor: 5, awayFor: 0, faded: true, solidKey: true) == .unfade)
    }

    @Test func theHandleAtTheLeftEndStaysSolidSoTheBarCanBeMoved() {
        #expect(!zone.isNear(pointer: CGPoint(x: 230, y: 100), bar: bar, wasNear: false))
        // also on the way in from the left and from above, at the bar's edge margin
        #expect(!zone.isNear(pointer: CGPoint(x: 197, y: 160), bar: bar, wasNear: false))
        #expect(zone.isNear(pointer: CGPoint(x: 300, y: 100), bar: bar, wasNear: false))
    }

    @Test func aPointerThatRestsOnTheFadedBarBringsItBack() {
        #expect(policy.action(near: true, nearFor: 3, awayFor: 0, faded: true, solidKey: false, stillFor: 1) == .none)
        #expect(policy.action(near: true, nearFor: 3, awayFor: 0, faded: true, solidKey: false, stillFor: 3) == .unfade)
    }

    @Test func aRestedBarStaysSolidUntilThePointerHasGone() {
        #expect(policy.action(near: true, nearFor: 30, awayFor: 0, faded: false, solidKey: false, stillFor: 0, rested: true) == .none)
        #expect(policy.action(near: true, nearFor: 0.6, awayFor: 0, faded: false, solidKey: false, stillFor: 0, rested: false) == .fade)
    }
}
