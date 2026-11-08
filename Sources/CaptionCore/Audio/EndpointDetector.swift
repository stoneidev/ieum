import Foundation

/// Notices the end of an utterance: speech followed by a pause.
///
/// "Speech" is anything clearly above the room's noise floor, which is tracked continuously, so the detector keeps
/// working in a noisy meeting room where the level never drops to digital silence.
public struct EndpointDetector: Sendable {
    public let pause: TimeInterval
    public let minimumSpeech: TimeInterval
    /// Level (dB) above the tracked noise floor that counts as speech.
    public let marginDB: Float
    /// Never treat anything quieter than this as speech.
    public let absoluteFloorDB: Float

    /// Recent levels, used to find the quietest moment of the last few seconds.
    private var recent: [(level: Float, duration: TimeInterval)] = []
    private var recentTotal: TimeInterval = 0
    private let windowSeconds: TimeInterval = 5
    private var speech: TimeInterval = 0
    private var silence: TimeInterval = 0
    /// How long the pause had lasted when `ingest` last returned true, so the caller can tell when the speech ended.
    public private(set) var lastPause: TimeInterval = 0

    public init(pause: TimeInterval = 0.7, minimumSpeech: TimeInterval = 0.3, marginDB: Float = 12, absoluteFloorDB: Float = -50) {
        self.pause = pause
        self.minimumSpeech = minimumSpeech
        self.marginDB = marginDB
        self.absoluteFloorDB = absoluteFloorDB
    }

    /// Feeds one audio chunk. Returns true exactly once per utterance, when its closing pause has lasted long enough.
    public mutating func ingest(levelDB: Float, duration: TimeInterval) -> Bool {
        remember(levelDB, duration: duration)
        if levelDB > max(noiseFloor + marginDB, absoluteFloorDB) {
            speech += duration
            silence = 0
            return false
        }
        silence += duration
        guard speech >= minimumSpeech, silence >= pause else { return false }
        lastPause = silence
        speech = 0
        silence = 0
        return true
    }

    /// The quietest level of the last few seconds, but never above `maxFloorDB`: when the history holds only speech
    /// (the stream began mid-sentence, or someone talks without a break) the speech itself must not become the floor.
    private var noiseFloor: Float {
        min(recent.map(\.level).min() ?? maxFloorDB, maxFloorDB)
    }

    private let maxFloorDB: Float = -40

    private mutating func remember(_ level: Float, duration: TimeInterval) {
        recent.append((max(level, -100), duration))
        recentTotal += duration
        while recentTotal > windowSeconds, recent.count > 1 {
            recentTotal -= recent.removeFirst().duration
        }
    }
}
