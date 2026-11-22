import Foundation
import Testing

@testable import CaptionCore

@Suite("Endpoint detector")
struct EndpointDetectorTests {
    /// Feeds `seconds` of constant level in 100 ms chunks and returns when an endpoint fired (nil if none).
    private func feed(_ detector: inout EndpointDetector, level: Float, seconds: Double) -> Double? {
        var t = 0.0
        while t < seconds {
            t += 0.1
            if detector.ingest(levelDB: level, duration: 0.1) { return t }
        }
        return nil
    }

    @Test func defaultPauseMatchesEngineOptions() {
        #expect(EndpointDetector().pause == 0.4)
        #expect(EngineOptions().pauseFinalization == 0.4)
    }

    @Test func firesAfterSpeechFollowedByAPause() {
        var d = EndpointDetector()
        #expect(feed(&d, level: -90, seconds: 1) == nil)      // quiet start: nothing yet
        #expect(feed(&d, level: -20, seconds: 2) == nil)      // speaking
        // 50 ms steps: must stay quiet through 0.35 s and fire exactly at the 0.4 s threshold.
        var firedAt: Double?
        var t = 0.0
        while t < 1.0 {
            t += 0.05
            if d.ingest(levelDB: -90, duration: 0.05) {
                firedAt = t
                break
            }
            if t < 0.4 { #expect(firedAt == nil) }
        }
        #expect(firedAt == 0.4)
    }

    @Test func firesOncePerUtteranceNotRepeatedlyDuringTheSilence() {
        var d = EndpointDetector()
        _ = feed(&d, level: -20, seconds: 1)
        #expect(feed(&d, level: -90, seconds: 0.9) != nil)
        #expect(feed(&d, level: -90, seconds: 3) == nil)
    }

    @Test func aShortBlipIsNotAnUtterance() {
        var d = EndpointDetector()
        _ = feed(&d, level: -90, seconds: 1)
        _ = feed(&d, level: -20, seconds: 0.1)
        #expect(feed(&d, level: -90, seconds: 2) == nil)
    }

    @Test func aBriefPauseInsideASentenceIsNotAnEndpoint() {
        var d = EndpointDetector()
        _ = feed(&d, level: -20, seconds: 1)
        // Under the 0.4 s rule a short hesitation must not close the sentence.
        #expect(feed(&d, level: -90, seconds: 0.3) == nil)
        #expect(feed(&d, level: -20, seconds: 1) == nil)
    }

    @Test func worksInANoisyRoomWhereSilenceNeverReachesDigitalZero() {
        var d = EndpointDetector()
        _ = feed(&d, level: -42, seconds: 3)                  // room noise
        _ = feed(&d, level: -22, seconds: 2)                  // voice, 20 dB above the noise
        #expect(feed(&d, level: -42, seconds: 2) != nil)      // back to room noise is a pause
    }

    @Test func continuousNoiseWithoutVoiceNeverFires() {
        var d = EndpointDetector()
        #expect(feed(&d, level: -42, seconds: 20) == nil)
    }

    @Test func twoUtterancesGiveTwoEndpoints() {
        var d = EndpointDetector()
        var count = 0
        for _ in 0..<2 {
            _ = feed(&d, level: -20, seconds: 1)
            if feed(&d, level: -90, seconds: 1.2) != nil { count += 1 }
        }
        #expect(count == 2)
    }
}
