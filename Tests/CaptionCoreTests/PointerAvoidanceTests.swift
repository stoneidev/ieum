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
        // the right 170 points hold the text size, panel and menu buttons
        #expect(!zone.isNear(pointer: CGPoint(x: 1100, y: 100), bar: bar, wasNear: false))
        #expect(!zone.isNear(pointer: CGPoint(x: 1100, y: 100), bar: bar, wasNear: true))
        #expect(zone.isNear(pointer: CGPoint(x: 1000, y: 100), bar: bar, wasNear: false))
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
}
