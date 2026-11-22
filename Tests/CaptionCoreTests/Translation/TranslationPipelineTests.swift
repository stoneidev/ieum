import Foundation
import Testing

@testable import CaptionCore

/// A translator with a controllable delay, so ordering and dropping behavior is deterministic enough to assert.
private struct FakeTranslator: TextTranslator {
    var delay: Duration = .milliseconds(120)
    var failing: Set<String> = []
    func translate(_ text: String) async throws -> String {
        try await Task.sleep(for: delay)
        if failing.contains(text) { throw TranslationUnavailable("boom: \(text)") }
        return "T(\(text))"
    }
}

private func collect(_ pipeline: TranslationPipeline) -> Task<[TranslationPipeline.Output], Never> {
    Task {
        var all: [TranslationPipeline.Output] = []
        for await output in pipeline.outputs { all.append(output) }
        return all
    }
}

@Suite("Translation pipeline")
struct TranslationPipelineTests {
    @Test func interimLatestWinsAndNeverPilesUp() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator())
        let results = collect(pipeline)
        await pipeline.submitInterim("aa")        // starts translating immediately
        try await Task.sleep(for: .milliseconds(20))
        await pipeline.submitInterim("ab")
        await pipeline.submitInterim("ac")
        await pipeline.submitInterim("ad")        // only this one may run next
        try await Task.sleep(for: .milliseconds(500))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == [
            .interim(source: "aa", translation: "T(aa)"),
            .interim(source: "ad", translation: "T(ad)"),
        ])
    }

    @Test func finalsAreNeverDroppedAndKeepTheirOrder() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(60)))
        let results = collect(pipeline)
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() { await pipeline.submitFinal(id: id, text: "s\(index)") }
        try await Task.sleep(for: .milliseconds(600))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == ids.enumerated().map { .final(id: $0.element, translation: "T(s\($0.offset))") })
    }

    @Test func interimInFlightWhenSentenceFinalizesIsDiscarded() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator())
        let results = collect(pipeline)
        let id = UUID()
        await pipeline.submitInterim("hello wor")   // in flight
        try await Task.sleep(for: .milliseconds(20))
        await pipeline.submitInterim("hello worl")  // pending
        await pipeline.submitFinal(id: id, text: "hello world")
        try await Task.sleep(for: .milliseconds(600))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == [.final(id: id, translation: "T(hello world)")])
    }

    @Test func aFinalDoesNotWaitBehindARunningInterimTranslation() async throws {
        // Interim translations are slow (400 ms); the final's own translator is quick. The final must not queue behind it.
        struct Slow: TextTranslator { func translate(_ text: String) async throws -> String { try await Task.sleep(for: .milliseconds(400)); return "slow(\(text))" } }
        struct Quick: TextTranslator { func translate(_ text: String) async throws -> String { try await Task.sleep(for: .milliseconds(30)); return "quick(\(text))" } }
        let pipeline = TranslationPipeline(translator: Quick(), interimTranslator: Slow())
        let results = collect(pipeline)
        let id = UUID()
        await pipeline.submitInterim("next sentence")      // starts the slow translation
        try await Task.sleep(for: .milliseconds(20))
        let before = ContinuousClock.now
        await pipeline.submitFinal(id: id, text: "one")
        try await Task.sleep(for: .milliseconds(150))
        let waited = before.duration(to: ContinuousClock.now)
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs.contains(.final(id: id, translation: "quick(one)")))
        #expect(waited < .milliseconds(400))
        // The interim result for the previous sentence is stale once the sentence is final.
        #expect(!outputs.contains(.interim(source: "next sentence", translation: "slow(next sentence)")))
    }

    @Test func aNewInterimAfterAFinalStillGetsTranslated() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(60)), interimTranslator: FakeTranslator(delay: .milliseconds(60)))
        let results = collect(pipeline)
        let id = UUID()
        await pipeline.submitFinal(id: id, text: "one")
        await pipeline.submitInterim("next sentence")
        try await Task.sleep(for: .milliseconds(400))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs.count == 2)
        #expect(outputs.contains(.final(id: id, translation: "T(one)")))
        #expect(outputs.contains(.interim(source: "next sentence", translation: "T(next sentence)")))
    }

    @Test func sameInterimTextIsNotTranslatedTwice() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(30)))
        let results = collect(pipeline)
        await pipeline.submitInterim("same text")
        try await Task.sleep(for: .milliseconds(150))
        await pipeline.submitInterim("same text")
        try await Task.sleep(for: .milliseconds(150))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == [.interim(source: "same text", translation: "T(same text)")])
    }

    @Test func tinyInterimTextIsIgnored() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(10)))
        let results = collect(pipeline)
        await pipeline.submitInterim("a")
        await pipeline.submitInterim("  ")
        try await Task.sleep(for: .milliseconds(100))
        await pipeline.close()
        #expect(await results.value.isEmpty)
    }

    @Test func failuresAreReportedAndTheNextRequestStillWorks() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(30), failing: ["bad", "worse"]))
        let results = collect(pipeline)
        let badID = UUID(), goodID = UUID()
        await pipeline.submitFinal(id: badID, text: "bad")
        await pipeline.submitFinal(id: goodID, text: "good")
        try await Task.sleep(for: .milliseconds(300))
        await pipeline.submitInterim("worse")
        try await Task.sleep(for: .milliseconds(200))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == [
            .failed(id: badID, message: "boom: bad"),
            .final(id: goodID, translation: "T(good)"),
            .failed(id: nil, message: "boom: worse"),
        ])
    }

    @Test func aHungRequestIsSkippedSoLaterOnesStillRun() async throws {
        struct Hanging: TextTranslator {
            func translate(_ text: String) async throws -> String {
                if text == "hang" { try await Task.sleep(for: .seconds(30)) }
                return "T(\(text))"
            }
        }
        let pipeline = TranslationPipeline(translator: Hanging(), requestTimeout: .milliseconds(150))
        let results = collect(pipeline)
        let hungID = UUID(), okID = UUID()
        await pipeline.submitFinal(id: hungID, text: "hang")
        await pipeline.submitFinal(id: okID, text: "fine")
        try await Task.sleep(for: .milliseconds(700))
        await pipeline.close()
        let outputs = await results.value
        #expect(outputs == [
            .failed(id: hungID, message: "The translation took too long and was skipped."),
            .final(id: okID, translation: "T(fine)"),
        ])
    }

    @Test func closeEndsTheStreamAndIgnoresLaterWork() async throws {
        let pipeline = TranslationPipeline(translator: FakeTranslator(delay: .milliseconds(10)))
        let results = collect(pipeline)
        await pipeline.close()
        await pipeline.submitFinal(id: UUID(), text: "late")
        await pipeline.submitInterim("late too")
        #expect(await results.value.isEmpty)
    }

    @Test func unavailableTranslatorReasonIsReadable() async {
        // On this SDK the real translator is only built for macOS 26.4+; the message must always be actionable.
        let result = await SystemTranslation.makeTranslator(from: "xx", to: "yy")
        if case .failure(let reason) = result {
            #expect(!reason.message.isEmpty)
        }
    }
}
