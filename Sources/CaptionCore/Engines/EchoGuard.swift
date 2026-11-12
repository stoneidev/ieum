import Foundation

/// In a call the microphone can hear the other side's voice coming out of the speakers. That leak is recognized as
/// well, in the wrong language (garbled text) or in the other side's own words. This drops such results from the
/// microphone so that only what the person at this Mac said stays.
public struct EchoGuard {
    public struct Config: Sendable {
        /// A microphone result that looks less like the microphone's language than this is noise or a leak.
        public var minimumPlausibility = 0.35
        /// How far back the other side's sentences are remembered for comparison.
        public var memorySeconds: TimeInterval = 15
        /// Share of a microphone sentence that must be found in a recent sentence from the other side to call it an echo.
        public var overlapThreshold = 0.6
        public init() {}
    }

    private let config: Config
    private let plausibility: @Sendable (String, String) -> Double
    private var recent: [(text: String, time: Date)] = []

    public init(config: Config = Config(), plausibility: @escaping @Sendable (String, String) -> Double = LanguageArbiter.textPlausibility) {
        self.config = config
        self.plausibility = plausibility
    }

    /// Remember a sentence the other side said (system audio), final or in progress.
    public mutating func noteTheirs(_ text: String, at time: Date) {
        let normalized = Self.normalize(text)
        guard normalized.count >= 2 else { return }
        recent.removeAll { time.timeIntervalSince($0.time) > config.memorySeconds }
        recent.append((normalized, time))
    }

    /// Whether a microphone result should be dropped as an echo or noise. `locale` is the language the person speaks.
    public func isEcho(_ text: String, locale: String, at time: Date) -> Bool {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return true }
        // Short results say little about their language; judge only text long enough for the language check.
        if normalized.count >= 6, plausibility(text, locale) < config.minimumPlausibility { return true }
        guard normalized.count >= 4 else { return false }
        for other in recent where time.timeIntervalSince(other.time) <= config.memorySeconds {
            if Self.overlap(normalized, other.text) >= config.overlapThreshold { return true }
        }
        return false
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Share of `a`'s character pairs that also occur in `b` (0...1); robust to small recognition differences.
    static func overlap(_ a: String, _ b: String) -> Double {
        func pairs(_ s: String) -> [String] {
            let c = Array(s)
            return c.count < 2 ? [s] : (0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) }
        }
        let mine = pairs(a)
        guard !mine.isEmpty else { return 0 }
        var pool: [String: Int] = [:]
        for pair in pairs(b) { pool[pair, default: 0] += 1 }
        var found = 0
        for pair in mine {
            if let n = pool[pair], n > 0 { found += 1; pool[pair] = n - 1 }
        }
        return Double(found) / Double(mine.count)
    }
}
