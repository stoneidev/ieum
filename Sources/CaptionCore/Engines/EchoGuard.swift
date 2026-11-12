import Foundation

/// In a call the microphone can hear the other side's voice coming out of the speakers, and it is recognized too.
/// When the microphone's recognizer speaks the same language as the other side, the result is almost the other side's
/// sentence again; this drops those, so that only what the person at this Mac said stays. A leak recognized in another
/// language comes out as unrelated text and cannot be told apart from speech by its words; echo cancellation on the
/// default microphone (and headphones) are what keep that out.
public struct EchoGuard {
    public struct Config: Sendable {
        /// A microphone sentence shorter than this is never called an echo: a short answer that repeats a word of the
        /// other side ("Thursday") is just an answer.
        public var minimumOverlapCheck = 12
        /// How far back the other side's sentences are remembered for comparison.
        public var memorySeconds: TimeInterval = 15
        /// Share of a microphone sentence that must be found in a recent sentence from the other side to call it an echo.
        public var overlapThreshold = 0.75
        public init() {}
    }

    private let config: Config
    private var recent: [(pairs: [String: Int], time: Date)] = []

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Remember a sentence the other side said (system audio), final or in progress.
    public mutating func noteTheirs(_ text: String, at time: Date) {
        let normalized = Self.normalize(text)
        guard normalized.count >= 2 else { return }
        recent.removeAll { time.timeIntervalSince($0.time) > config.memorySeconds }
        recent.append((Self.pairCounts(normalized), time))
    }

    /// Whether a microphone result should be dropped as an echo of the other side.
    public func isEcho(_ text: String, at time: Date) -> Bool {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return true }
        guard normalized.count >= config.minimumOverlapCheck else { return false }
        let mine = Self.pairs(normalized)
        for other in recent where time.timeIntervalSince(other.time) <= config.memorySeconds {
            if Self.overlap(mine, in: other.pairs) >= config.overlapThreshold { return true }
        }
        return false
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func pairs(_ s: String) -> [String] {
        let c = Array(s)
        return c.count < 2 ? [s] : (0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) }
    }

    static func pairCounts(_ s: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for pair in pairs(s) { counts[pair, default: 0] += 1 }
        return counts
    }

    /// Share of `mine` (character pairs of one sentence) that also occur in `pool` (0...1); robust to small recognition differences.
    static func overlap(_ mine: [String], in pool: [String: Int]) -> Double {
        guard !mine.isEmpty else { return 0 }
        var left = pool
        var found = 0
        for pair in mine {
            if let n = left[pair], n > 0 { found += 1; left[pair] = n - 1 }
        }
        return Double(found) / Double(mine.count)
    }
}
