import Foundation
import Testing

@testable import CaptionCore

@Suite("Input level advice")
struct InputLevelAdvisorTests {
    private func feed(_ advisor: inout InputLevelAdvisor, db: Float, seconds: Double, chunk: Double = 0.1) {
        for _ in 0..<Int((seconds / chunk).rounded()) { advisor.ingest(levelDB: db, duration: chunk) }
    }

    @Test func silenceIsReportedOnlyAfterAFewSeconds() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -100, seconds: 3)
        #expect(advisor.advice == .good)
        feed(&advisor, db: -100, seconds: 4)
        #expect(advisor.advice == .silent)
    }

    @Test func aRoomWithNoiseIsNotSilence() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -52, seconds: 10)
        #expect(advisor.advice == .good)
    }

    @Test func speechClearsTheSilenceAtOnce() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -100, seconds: 10)
        #expect(advisor.advice == .silent)
        feed(&advisor, db: -25, seconds: 0.5)
        #expect(advisor.advice == .good)
    }

    @Test func aLongStretchThatNeverReachesSpeechIsTooQuiet() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -50, seconds: 20)
        #expect(advisor.advice == .good)
        feed(&advisor, db: -50, seconds: 6)
        #expect(advisor.advice == .tooQuiet)
    }

    @Test func oneSentenceInAMinuteOfPausesIsFine() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -50, seconds: 20)
        feed(&advisor, db: -28, seconds: 1)
        feed(&advisor, db: -50, seconds: 20)
        #expect(advisor.advice == .good)
    }

    @Test func distortionIsReported() {
        var advisor = InputLevelAdvisor()
        feed(&advisor, db: -3, seconds: 2)
        #expect(advisor.advice == .tooLoud)
        feed(&advisor, db: -30, seconds: 3)
        #expect(advisor.advice == .good)
    }

    @Test func theMeterRisesFastAndFallsSlowly() {
        var advisor = InputLevelAdvisor()
        advisor.ingest(levelDB: -20, duration: 0.1)
        let high = advisor.meter
        advisor.ingest(levelDB: -90, duration: 0.1)
        #expect(high > 0.7)
        #expect(advisor.meter < high && advisor.meter > 0.5)
        feed(&advisor, db: -90, seconds: 1)
        #expect(advisor.meter == 0)
    }

    @Test func theMonitorPublishesChangesAtOnce() {
        final class Box: @unchecked Sendable { var seen: [InputAdvice] = [] }
        let box = Box()
        let monitor = InputLevelMonitor { advice, _ in box.seen.append(advice) }
        for _ in 0..<80 { monitor.ingest(levelDB: -100, duration: 0.1) }
        #expect(box.seen.last == .silent)
        #expect(box.seen.contains(.good))
    }
}
