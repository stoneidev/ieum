import Foundation
import Testing

@testable import CaptionCore

@Suite("Reply helper")
struct ReplyHelperTests {
    @Test func inputIsTidiedAndEmptyInputIsRefused() {
        #expect(ReplyHelper.prepare("  다음 주까지   가능합니다  \n") == "다음 주까지 가능합니다")
        #expect(ReplyHelper.prepare("한 줄\n두 줄") == "한 줄 두 줄")
        #expect(ReplyHelper.prepare("   \n  ") == nil)
        #expect(ReplyHelper.prepare("") == nil)
    }

    @Test func aVeryLongInputIsCut() {
        let long = String(repeating: "가", count: 2_000)
        #expect(ReplyHelper.prepare(long)?.count == ReplyHelper.maxCharacters)
    }

    @Test func aPolishedEnglishReplyMustStayEnglishAndReasonable() {
        let literal = "I can finish it by next Friday."
        #expect(ReplyHelper.acceptsPolished(literal: literal, candidate: "I should be able to wrap it up by next Friday.", target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: literal, candidate: "다음 주 금요일까지 끝낼 수 있습니다.", target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: literal, candidate: "", target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: literal, candidate: String(repeating: "word ", count: 200), target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: String(repeating: "word ", count: 20), candidate: "ok", target: .english))
        // a rewrite that drops a good part of the sentence is not a smoother version of it
        #expect(!ReplyHelper.acceptsPolished(literal: "I can't decide the budget, so I'll discuss it with the team leader first.", candidate: "I'll discuss the budget with the team leader first.", target: .english))
    }

    @Test func aSmootherSentenceMustSayTheSameThing() {
        let literal = "I don't think it will be possible until next Friday, can I share it on Monday?"
        // the question became a statement
        #expect(!ReplyHelper.acceptsPolished(literal: literal, candidate: "I don't think it will be possible until next Friday, so I can share it on Monday.", target: .english))
        // a question stays a question
        #expect(ReplyHelper.acceptsPolished(literal: literal, candidate: "I don't think I can make it by next Friday. Could I share it on Monday?", target: .english))
        // numbers and names are kept
        #expect(!ReplyHelper.acceptsPolished(literal: "Maria will send 3 files on Tuesday.", candidate: "Maria will send some files on Tuesday.", target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: "Maria will send 3 files on Tuesday.", candidate: "She will send 3 files on Tuesday.", target: .english))
        #expect(ReplyHelper.acceptsPolished(literal: "Maria will send 3 files on Tuesday.", candidate: "Maria is going to send 3 files on Tuesday.", target: .english))
    }

    @Test func theStartOfEverySentenceIsNotTakenForAName() {
        // the second sentence starts with a capital too
        #expect(ReplyHelper.acceptsPolished(literal: "Yes. Tomorrow works for me.", candidate: "Yes, tomorrow works for me.", target: .english))
        #expect(ReplyHelper.acceptsPolished(literal: "Sounds good, I can do it on Friday.", candidate: "That sounds good. I can do it on Friday.", target: .english))
        // a real name in the second sentence is still a name
        #expect(!ReplyHelper.acceptsPolished(literal: "Yes. Maria will send it on Friday.", candidate: "Yes, she will send it on Friday.", target: .english))
        // curly apostrophes are the same as straight ones
        #expect(ReplyHelper.acceptsPolished(literal: "I\u{2019}ll send Anna\u{2019}s file on Friday.", candidate: "I will send Anna's file on Friday.", target: .english))
    }

    @Test func aContractionAtTheStartIsNotAName() {
        // a machine translation says "It's available"; the fix for the missing subject must be accepted
        #expect(ReplyHelper.acceptsPolished(literal: "It's available at 3 p.m. next Tuesday.", candidate: "I'm available next Tuesday at 3 p.m.", target: .english))
        #expect(ReplyHelper.acceptsPolished(literal: "We'll check that part and reply by tomorrow.", candidate: "I'll check that part and get back to you by tomorrow.", target: .english))
        #expect(!ReplyHelper.acceptsPolished(literal: "It's available at 3 p.m. next Tuesday.", candidate: "I'm available next Wednesday at 3 p.m.", target: .english))
    }

    @Test func otherTargetLanguagesAreCheckedByScript() {
        #expect(ReplyHelper.acceptsPolished(literal: "다음 주까지 가능합니다", candidate: "다음 주까지는 가능할 것 같습니다", target: .korean))
        #expect(!ReplyHelper.acceptsPolished(literal: "다음 주까지 가능합니다", candidate: "It is possible until next week", target: .korean))
        #expect(ReplyHelper.acceptsPolished(literal: "来週までに可能です", candidate: "来週までなら大丈夫です", target: .japanese))
        #expect(ReplyHelper.acceptsPolished(literal: "下周之前可以完成", candidate: "下周之前应该可以完成", target: .chinese))
    }

    @Test func historyKeepsTheNewestFirstAndDropsRepeats() {
        var history = ReplyHistory()
        history.add(source: "a", reply: "A1")
        history.add(source: "b", reply: "B1")
        history.add(source: "a", reply: "A2")
        #expect(history.items.map(\.reply) == ["A2", "B1"])
    }

    @Test func historyHasACapacity() {
        var history = ReplyHistory()
        for number in 1...9 { history.add(source: "s\(number)", reply: "r\(number)") }
        #expect(history.items.count == ReplyHistory.capacity)
        #expect(history.items.first?.reply == "r9")
    }

    @Test func theFirstFinishedSentenceIsTaken() async throws {
        let stream = AsyncThrowingStream<TranscriptionEvent, Error> { continuation in
            continuation.yield(TranscriptionEvent(text: "다음", isFinal: false, locale: "ko-KR", timestamp: Date()))
            continuation.yield(TranscriptionEvent(text: "다음 주 가능합니다", isFinal: true, locale: "ko-KR", timestamp: Date()))
            continuation.yield(TranscriptionEvent(text: "그리고", isFinal: true, locale: "ko-KR", timestamp: Date()))
            continuation.finish()
        }
        #expect(try await ReplyHelper.firstUtterance(from: stream) == "다음 주 가능합니다")
    }

    @Test func ifTheStreamEndsFirstWhatWasHeardIsUsed() async throws {
        let partial = AsyncThrowingStream<TranscriptionEvent, Error> { continuation in
            continuation.yield(TranscriptionEvent(text: "다음 주", isFinal: false, locale: "ko-KR", timestamp: Date()))
            continuation.finish()
        }
        #expect(try await ReplyHelper.firstUtterance(from: partial) == "다음 주")
        let silence = AsyncThrowingStream<TranscriptionEvent, Error> { $0.finish() }
        #expect(try await ReplyHelper.firstUtterance(from: silence) == nil)
    }

    @Test func everyLanguageHasInstructionsThatAskForNoExtras() {
        for language in SpokenLanguage.allCases {
            let text = ReplyPrompt.instructions(for: language)
            #expect(text.count > 80)
        }
        #expect(ReplyPrompt.instructions(for: .english).contains("without quotes or explanation"))
    }
}
