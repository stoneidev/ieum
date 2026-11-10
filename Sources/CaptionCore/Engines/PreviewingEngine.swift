import AVFoundation
import Foundation
import Speech

/// Shows words sooner. The modern recognizer reports in bursts about once a second (the first words after roughly
/// a second); the legacy recognizer streams word by word (first word after about half a second, then every
/// quarter second). This engine runs both on the same audio and shows the legacy words for the sentence being
/// spoken. Every finished sentence still comes from the modern recognizer, which is the more accurate one.
///
/// The legacy text is only used until the modern recognizer finishes a sentence, because the legacy session keeps
/// accumulating text across sentences and cannot be told which part is already final. It is used again when the
/// legacy session ends, which happens after a pause.
public final class PreviewingEngine: TranscriberEngine, @unchecked Sendable {
    public var name: String { "\(primary.name) + early words" }

    private let primary: any TranscriberEngine
    private let preview: any TranscriberEngine

    init(primary: any TranscriberEngine, preview: any TranscriberEngine) {
        self.primary = primary
        self.preview = preview
    }

    /// Whether the legacy recognizer can serve as the early-words source for `localeID`: it must have an on-device
    /// model and the Speech Recognition permission. Asks for the permission when it was never asked.
    static func makePreviewEngine(localeID: String, options: EngineOptions) async -> (any TranscriberEngine)? {
        guard let engine = try? OnDeviceSpeechEngine(localeID: localeID, options: options) else { return nil }
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        return status == .authorized && SFSpeechRecognizer(locale: Locale(identifier: localeID))?.isAvailable == true ? engine : nil
    }

    public func events(from capture: any AudioCapture) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        let shared = SharedAudioCapture(source: capture, branchCount: 2)
        let branches = shared.branches
        let primary = self.primary
        let preview = self.preview
        let streams: (AsyncThrowingStream<TranscriptionEvent, Error>, AsyncThrowingStream<TranscriptionEvent, Error>)
        do {
            streams = try await withThrowingTaskGroup(of: (Int, AsyncThrowingStream<TranscriptionEvent, Error>).self) { group in
                group.addTask { (0, try await primary.events(from: branches[0])) }
                group.addTask { (1, try await preview.events(from: branches[1])) }
                var ordered = [AsyncThrowingStream<TranscriptionEvent, Error>?](repeating: nil, count: 2)
                do {
                    for try await (index, stream) in group { ordered[index] = stream }
                } catch {
                    // A consumer that failed to start would leave the other waiting for audio forever.
                    shared.abort(error)
                    throw error
                }
                return (ordered[0]!, ordered[1]!)
            }
        } catch {
            await primary.stop()
            await preview.stop()
            throw error
        }

        let merger = Merger()
        return AsyncThrowingStream { continuation in
            let driver = Task { await merger.run(primary: streams.0, preview: streams.1, into: continuation) }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }

    public func stop() async {
        await primary.stop()
        await preview.stop()
    }

    /// Decides, event by event, which recognizer's interim words are shown.
    ///
    /// A legacy session keeps accumulating text across sentences, so after the modern recognizer finishes a sentence
    /// the legacy text still starts with it. The finished part is skipped by counting letters (word splitting differs
    /// between the recognizers, letter counts nearly do not) and cutting at the nearest word boundary.
    struct Gate {
        /// Letters of the sentences the modern recognizer finished during the current legacy session.
        private var finishedLetters = 0
        /// The current legacy session has produced words.
        private var sessionHasWords = false
        /// Early words exist for the sentence being spoken, so the modern interim words are not shown.
        private(set) var previewSeen = false
        private var previewLost = false

        mutating func primary(_ event: TranscriptionEvent) -> Bool {
            if event.isFinal {
                if sessionHasWords { finishedLetters += Self.letterCount(event.text) }
                previewSeen = false
                return true
            }
            // Until early words exist for this sentence, the modern interim words are better than nothing.
            return previewLost || !previewSeen
        }

        /// The legacy recognizer is gone: the modern interim words must show again.
        mutating func lostPreview() {
            previewLost = true
            previewSeen = false
        }

        /// The event to show for a legacy event, or nil when it adds nothing.
        mutating func preview(_ event: TranscriptionEvent) -> TranscriptionEvent? {
            if event.isFinal {
                // The legacy session ended (a pause): its next words belong to a new sentence.
                finishedLetters = 0
                sessionHasWords = false
                previewSeen = false
                return nil
            }
            guard !previewLost else { return nil }
            sessionHasWords = true
            let rest = Self.dropping(letters: finishedLetters, from: event.text)
            guard !rest.isEmpty else {
                previewSeen = false
                return nil
            }
            previewSeen = true
            return TranscriptionEvent(
                text: rest, isFinal: false, locale: event.locale, timestamp: event.timestamp,
                audioStart: event.audioStart, audioEnd: event.audioEnd, confidence: event.confidence
            )
        }

        static func letterCount(_ text: String) -> Int {
            text.unicodeScalars.reduce(0) { $0 + (CharacterSet.alphanumerics.contains($1) ? 1 : 0) }
        }

        /// `text` without its first `letters` letters, cut at the word boundary nearest to that point.
        static func dropping(letters: Int, from text: String) -> String {
            guard letters > 0 else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            var seen = 0
            var cut = text.startIndex
            var boundaries: [(index: String.Index, letters: Int)] = [(text.startIndex, 0)]
            for index in text.indices {
                if text[index].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) { seen += 1 }
                let next = text.index(after: index)
                // Japanese and Chinese have no spaces between words, so every character is a place to cut.
                let unspaced = text[index].unicodeScalars.first.map { TextScript.isUnspaced($0.value) } ?? false
                if next == text.endIndex || text[next].isWhitespace || unspaced { boundaries.append((next, seen)) }
            }
            if let best = boundaries.min(by: { abs($0.letters - letters) < abs($1.letters - letters) }) { cut = best.index }
            // The legacy text has not reached the end of the finished sentences yet.
            if seen <= letters, seen < letters - 2 { return "" }
            let rest = String(text[cut...])
            // A cut right before the closing 。 would leave it standing alone at the start.
            let leading = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(CharacterSet(charactersIn: "。、，！？"))
            return rest.trimmingCharacters(in: cut == text.startIndex ? .whitespacesAndNewlines : leading)
        }
    }

    private actor Merger {
        private var gate = Gate()
        private var continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?
        private var finished = false

        func run(
            primary: AsyncThrowingStream<TranscriptionEvent, Error>,
            preview: AsyncThrowingStream<TranscriptionEvent, Error>,
            into continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
        ) async {
            self.continuation = continuation
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [self] in
                    do {
                        for try await event in primary { await fromPrimary(event) }
                        await finish(nil)
                    } catch {
                        await finish(error)
                    }
                }
                group.addTask { [self] in
                    // The early words are a convenience: if that recognizer stops, captions go on without it.
                    do { for try await event in preview { await fromPreview(event) } } catch {}
                    await previewEnded()
                }
            }
        }

        private func fromPrimary(_ event: TranscriptionEvent) {
            if !finished, gate.primary(event) { continuation?.yield(event) }
        }

        private func fromPreview(_ event: TranscriptionEvent) {
            if !finished, let shown = gate.preview(event) { continuation?.yield(shown) }
        }

        private func previewEnded() {
            gate.lostPreview()
        }

        private func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        }
    }
}
