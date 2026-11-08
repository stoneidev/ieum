import Foundation

/// Anything that turns text in one language into another, entirely on this device.
public protocol TextTranslator: Sendable {
    func translate(_ text: String) async throws -> String
}

/// Feeds slow, one-at-a-time translators from a live caption stream with minimal lag.
///
/// - Interim text: only the newest one waits; anything older is dropped (latest wins), so lag never piles up.
/// - Finalized sentences: always translated, in order. They have a translator of their own, so a sentence that
///   just ended never waits behind the interim translation that is still running for it (which is stale anyway).
/// - An interim translation that was still in flight when its sentence became final is discarded as stale.
public actor TranslationPipeline {
    public enum Output: Sendable, Equatable {
        /// Translation of the newest interim text. `source` is the text that was translated.
        case interim(source: String, translation: String)
        /// Translation of the finalized sentence submitted with this `id`.
        case final(id: UUID, translation: String)
        /// A request failed; `id` is set for finalized sentences.
        case failed(id: UUID?, message: String)
    }

    public nonisolated let outputs: AsyncStream<Output>
    private nonisolated let continuation: AsyncStream<Output>.Continuation
    private let finalTranslator: any TextTranslator
    private let interimTranslator: any TextTranslator
    private let requestTimeout: Duration
    private var finals: [(id: UUID, text: String)] = []
    private var latestInterim: String?
    private var lastInterimSource = ""
    private var epoch = 0
    private var drainingFinals = false
    private var drainingInterims = false
    private var closed = false

    /// - Parameters:
    ///   - translator: translates finalized sentences.
    ///   - interimTranslator: translates the sentence being spoken. Pass a separate instance to run both at once;
    ///     it defaults to `translator`, which then serves one request at a time overall in practice.
    ///   - requestTimeout: a request that takes longer is reported as failed and the queue moves on.
    public init(translator: any TextTranslator, interimTranslator: (any TextTranslator)? = nil, requestTimeout: Duration = .seconds(10)) {
        finalTranslator = translator
        self.interimTranslator = interimTranslator ?? translator
        self.requestTimeout = requestTimeout
        (outputs, continuation) = AsyncStream.makeStream(of: Output.self, bufferingPolicy: .unbounded)
    }

    public func submitInterim(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed, trimmed.count >= 2, trimmed != lastInterimSource else { return }
        latestInterim = trimmed
        startDrainingInterims()
    }

    public func submitFinal(id: UUID, text: String) {
        guard !closed else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finals.append((id, trimmed))
        // The interim text just became this sentence: whatever was pending or in flight for it is stale.
        latestInterim = nil
        lastInterimSource = ""
        epoch += 1
        startDrainingFinals()
    }

    /// Stops accepting work and ends the output stream. Pending requests are dropped.
    public func close() {
        closed = true
        finals.removeAll()
        latestInterim = nil
        continuation.finish()
    }

    private func startDrainingFinals() {
        guard !drainingFinals else { return }
        drainingFinals = true
        Task { await drainFinals() }
    }

    private func startDrainingInterims() {
        guard !drainingInterims else { return }
        drainingInterims = true
        Task { await drainInterims() }
    }

    private func drainFinals() async {
        while !closed, !finals.isEmpty {
            let job = finals.removeFirst()
            do {
                let translation = try await translateWithTimeout(job.text, using: finalTranslator)
                if !closed { continuation.yield(.final(id: job.id, translation: translation)) }
            } catch {
                if !closed { continuation.yield(.failed(id: job.id, message: Self.describe(error))) }
            }
        }
        drainingFinals = false
    }

    private func drainInterims() async {
        while !closed, let text = latestInterim {
            latestInterim = nil
            let startedEpoch = epoch
            do {
                let translation = try await translateWithTimeout(text, using: interimTranslator)
                // Drop it when a sentence was finalized meanwhile; keep the text for de-duplication otherwise.
                if !closed, startedEpoch == epoch {
                    lastInterimSource = text
                    continuation.yield(.interim(source: text, translation: translation))
                }
            } catch {
                if !closed, startedEpoch == epoch { continuation.yield(.failed(id: nil, message: Self.describe(error))) }
            }
        }
        drainingInterims = false
    }

    /// Races the translator against a timer using unstructured tasks. A task group would wait for a hung,
    /// non-cancellable translation call; this lets the queue move on and simply ignores the late result.
    private func translateWithTimeout(_ text: String, using translator: any TextTranslator) async throws -> String {
        let timeout = self.requestTimeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let once = Once()
            let timer = Task {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled, once.claim() { continuation.resume(throwing: TranslationUnavailable("The translation took too long and was skipped.")) }
            }
            Task {
                do {
                    let result = try await translator.translate(text)
                    timer.cancel()
                    if once.claim() { continuation.resume(returning: result) }
                } catch {
                    timer.cancel()
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Why translation cannot be used right now, in words the user can act on.
public struct TranslationUnavailable: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Entry point that compiles on every SDK; the real translator needs the macOS 26.4 Translation API.
public enum SystemTranslation {
    /// - Parameters are BCP-47 language codes such as "en" and "ko".
    public static func makeTranslator(from source: String, to target: String) async -> Result<any TextTranslator, TranslationUnavailable> {
        #if compiler(>=6.2)
        if #available(macOS 26.4, *) {
            return await SystemTranslator.make(from: source, to: target)
        }
        #endif
        return .failure(TranslationUnavailable("Offline translation needs macOS 26.4 or later."))
    }
}
