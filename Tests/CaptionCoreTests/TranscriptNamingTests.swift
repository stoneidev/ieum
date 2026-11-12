import Foundation
import Testing

@testable import CaptionCore

@Suite("Transcript naming")
struct TranscriptNamingTests {
    @Test func namesAreCleanedForTheFileSystem() {
        #expect(TranscriptNaming.sanitize("  대책회의  ") == "대책회의")
        #expect(TranscriptNaming.sanitize("A/B: plan") == "A-B- plan")
        #expect(TranscriptNaming.sanitize("Weekly   sync") == "Weekly sync")
        #expect(TranscriptNaming.sanitize(".hidden") == "hidden")
        #expect(TranscriptNaming.sanitize("山田さんとの会議") == "山田さんとの会議")
        #expect(TranscriptNaming.sanitize("   ") == nil)
        #expect(TranscriptNaming.sanitize("...") == nil)
    }

    @Test func longNamesAreShortened() {
        let name = TranscriptNaming.sanitize(String(repeating: "가", count: 200))
        #expect(name?.count == TranscriptNaming.maxLength)
    }

    @Test func aRenameMovesTheTextFileAndItsExports() {
        let existing = [
            "transcript-2026-11-12_225806-ja-JP.txt", "transcript-2026-11-12_225806-ja-JP.srt",
            "transcript-2026-11-12_225806-ja-JP-2.srt", "transcript-2026-11-12_225806-ja-JP.md",
            "transcript-2026-11-11_072939-ja-JP.txt", "transcript-2026-11-12_225806-ja-JPX.srt",
        ]
        let plan = TranscriptNaming.renamePlan(oldBase: "transcript-2026-11-12_225806-ja-JP", title: "대책회의", existing: existing)
        #expect(plan?.newBase == "대책회의")
        #expect(Set(plan?.moves ?? []) == [
            .init(from: "transcript-2026-11-12_225806-ja-JP.txt", to: "대책회의.txt"),
            .init(from: "transcript-2026-11-12_225806-ja-JP.srt", to: "대책회의.srt"),
            .init(from: "transcript-2026-11-12_225806-ja-JP-2.srt", to: "대책회의-2.srt"),
            .init(from: "transcript-2026-11-12_225806-ja-JP.md", to: "대책회의.md"),
        ])
    }

    @Test func aTakenNameGetsANumber() {
        let plan = TranscriptNaming.renamePlan(oldBase: "a", title: "Weekly sync", existing: ["a.txt", "Weekly sync.txt", "Weekly sync 2.srt"])
        #expect(plan?.newBase == "Weekly sync 3")
        #expect(plan?.moves == [.init(from: "a.txt", to: "Weekly sync 3.txt")])
    }

    @Test func theSameNameOrAnEmptyOneChangesNothing() {
        #expect(TranscriptNaming.renamePlan(oldBase: "Weekly sync", title: "Weekly sync", existing: ["Weekly sync.txt"]) == nil)
        #expect(TranscriptNaming.renamePlan(oldBase: "Weekly sync", title: "  ", existing: ["Weekly sync.txt"]) == nil)
    }

    @Test func changingOnlyCapitalLettersIsAllowed() {
        let plan = TranscriptNaming.renamePlan(oldBase: "weekly sync", title: "Weekly sync", existing: ["weekly sync.txt"])
        #expect(plan?.newBase == "Weekly sync")
    }
}

@Suite("Transcript naming: minutes")
struct TranscriptNamingMinutesTests {
    @Test func theMinutesDraftFollowsARename() {
        let existing = [
            "a.txt", "a.md", "a-minutes.md", "a-minutes-2.md", "a-minutes-x.md", "a-minutes.srt", "a-2.srt",
        ]
        let plan = TranscriptNaming.renamePlan(oldBase: "a", title: "Budget", existing: existing)
        let moves = Set(plan?.moves.map { "\($0.from)>\($0.to)" } ?? [])
        #expect(moves == ["a.txt>Budget.txt", "a.md>Budget.md", "a-minutes.md>Budget-minutes.md",
                          "a-minutes-2.md>Budget-minutes-2.md", "a-2.srt>Budget-2.srt"])
    }
}

@Suite("Transcript naming: taken names")
struct TranscriptNamingTakenTests {
    @Test func aLeftoverMinutesFileMakesTheNameTaken() {
        let plan = TranscriptNaming.renamePlan(oldBase: "a", title: "Budget", existing: ["a.txt", "Budget-minutes.md"])
        #expect(plan?.newBase == "Budget 2")
    }
}
