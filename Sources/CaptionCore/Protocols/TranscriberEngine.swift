import AVFoundation
import Foundation

/// One transcription update, either a volatile partial or a finalized segment.
public struct TranscriptionEvent: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let locale: String
    public let timestamp: Date
    /// Audio-relative time range in seconds, when the engine provides it.
    public let audioStart: Double?
    public let audioEnd: Double?
    /// How sure the recognizer is, 0...1, when the engine reports it.
    public let confidence: Double?

    public init(
        text: String,
        isFinal: Bool,
        locale: String,
        timestamp: Date = Date(),
        audioStart: Double? = nil,
        audioEnd: Double? = nil,
        confidence: Double? = nil
    ) {
        self.text = text
        self.isFinal = isFinal
        self.locale = locale
        self.timestamp = timestamp
        self.audioStart = audioStart
        self.audioEnd = audioEnd
        self.confidence = confidence
    }
}

/// A captured audio buffer plus its measured RMS level.
/// `AVAudioPCMBuffer` is not `Sendable`; capture code hands over ownership and never touches it again.
public struct AudioChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public let levelDB: Float
    public let duration: TimeInterval
}

/// Accuracy/latency knobs shared by both engines.
public struct EngineOptions: Sendable, Equatable {
    /// Modern engine: report results sooner at the cost of some accuracy (`.fastResults`).
    public var fast = true
    /// Modern engine: hardware-accelerated voice activity detection. Apple warns that a VAD that drops
    /// speech lowers accuracy, so it can be switched off.
    public var useVAD = true
    /// Words and phrases the recognizer should favor (names, jargon).
    public var vocabulary: [String] = []
    /// Modern engine: after this many seconds of silence following speech, finalize the sentence at once instead
    /// of waiting for the recognizer to decide. Nil leaves the decision to the recognizer.
    public var pauseFinalization: TimeInterval? = 0.7
    /// Whether `EngineFactory` repairs the transcript with `vocabulary`. The app switches this off: it corrects
    /// the text itself, with the list as it is right now, not as it was when the session started.
    public var correctsTranscript = true
    /// Modern engine: also run the legacy recognizer and show its words for the sentence being spoken, which
    /// appear sooner. Finished sentences always come from the modern engine.
    public var showsWordsSooner = false

    public init(fast: Bool = true, useVAD: Bool = true, vocabulary: [String] = [], pauseFinalization: TimeInterval? = 0.7) {
        self.fast = fast
        self.useVAD = useVAD
        self.vocabulary = vocabulary
        self.pauseFinalization = pauseFinalization
    }

    /// One term per line; blank lines and `#` comments are ignored.
    public static func parseVocabulary(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

public protocol AudioCapture: Sendable {
    /// Starts capturing and returns the stream of buffers. The stream finishes after `stop()`.
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
}

public protocol TranscriberEngine: Sendable {
    var name: String { get }
    /// Starts `capture` and returns transcription events. The stream finishes once `stop()` was called
    /// (or the capture ended) and all pending results have been flushed.
    func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error>
    /// Stops audio capture; the event stream then drains and finishes on its own.
    func stop() async
}

public enum EngineError: LocalizedError {
    case unsupportedLocale(String)
    case engineUnavailable(String)
    case permissionDenied(String)
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let message),
             .engineUnavailable(let message),
             .permissionDenied(let message),
             .captureFailed(let message):
            return message
        }
    }

    /// Errors that mean "this engine cannot serve the request", so another engine may be tried.
    public var allowsFallback: Bool {
        switch self {
        case .unsupportedLocale, .engineUnavailable: return true
        case .permissionDenied, .captureFailed: return false
        }
    }
}
