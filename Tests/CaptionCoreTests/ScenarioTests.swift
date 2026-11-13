import Foundation
import Testing

@testable import CaptionCore

@Suite("Scenario")
struct ScenarioTests {
    @Test func aSeminarIsOnlyListenedTo() {
        #expect(!Scenario.seminar.allowsBothWays)
        #expect(!Scenario.seminar.allowsCall)
        #expect(Scenario.seminar.allowsSystemAudio)
    }

    @Test func aConversationIsInTheRoomAndAnswersEachOther() {
        #expect(Scenario.conversation.allowsBothWays && Scenario.conversation.defaultsToBothWays)
        #expect(!Scenario.conversation.allowsSystemAudio && !Scenario.conversation.allowsCall)
    }

    @Test func onlyAMeetingOffersTheCallSource() {
        #expect(Scenario.allCases.filter(\.allowsCall) == [.meeting])
        #expect(Scenario.meeting.prefersSystemAudio)
    }

    @Test func theDefaultSetupSwitchesBothSidesPerSituation() {
        let one = MeetingSetup(heard: .english, shown: .korean)
        let both = MeetingSetup(heard: .english, shown: .korean, bothWays: true)
        #expect(Scenario.conversation.defaultSetup(from: one, bothWaysAvailable: true).bothWays)
        #expect(!Scenario.conversation.defaultSetup(from: one, bothWaysAvailable: false).bothWays)
        #expect(!Scenario.meeting.defaultSetup(from: both, bothWaysAvailable: true).bothWays)
        #expect(!Scenario.seminar.defaultSetup(from: both, bothWaysAvailable: true).bothWays)
        // captions only has nobody to answer
        let captionsOnly = MeetingSetup(heard: .english, shown: nil)
        #expect(!Scenario.conversation.defaultSetup(from: captionsOnly, bothWaysAvailable: true).bothWays)
    }

    @Test func oldSettingsBecomeTheClosestSituation() {
        let one = MeetingSetup(heard: .english, shown: .korean)
        let both = MeetingSetup(heard: .english, shown: .korean, bothWays: true)
        #expect(Scenario.migrated(setup: one, usesCall: true) == .meeting)
        #expect(Scenario.migrated(setup: both, usesCall: false) == .conversation)
        #expect(Scenario.migrated(setup: one, usesCall: false) == .meeting)
        // answering each other on system audio cannot be a conversation, which is in the room
        #expect(Scenario.migrated(setup: both, usesCall: false, usesSystemAudio: true) == .meeting)
    }

    @Test func eachSituationHasItsOwnNotes() {
        #expect(Scenario.seminar.minutes.sections == [.summary, .keyPoints, .questions])
        #expect(Scenario.meeting.minutes.sections == [.summary, .decisions, .actions, .questions])
        #expect(Scenario.conversation.minutes.sections == [.summary, .keyPoints, .actions])
    }
}

@Suite("Minutes normalization")
struct MinutesNormalizationTests {
    @Test func textIsTidied() {
        #expect(MinutesText.tidy("  - Ship the beta on Monday.  ") == "Ship the beta on Monday")
        #expect(MinutesText.tidy("1. 베타 출시\n계속") == "베타 출시 계속")
        #expect(MinutesText.tidy("• 来週開始。") == "来週開始")
        #expect(MinutesText.tidy("A summary sentence.", keepsStop: true) == "A summary sentence.")
        #expect(MinutesText.tidy("Is it ready?") == "Is it ready?")
    }

    @Test func emptyAnswersAreDropped() {
        for empty in ["None", "n/a", "없음", "해당 없음", "なし", "没有", "  ", "-", "None found."] {
            #expect(MinutesText.tidy(empty) == nil, "\(empty)")
        }
    }

    @Test func pointsDifferingOnlyInCaseAndPunctuationAreOne() {
        #expect(MinutesText.key("Update the Notes!") == MinutesText.key("update the notes"))
        #expect(MinutesText.key("릴리스 노트 업데이트") != MinutesText.key("릴리스 노트 공유"))
    }

    @Test func validationDropsNearDuplicatesAndOrdersByTheMeeting() {
        let minutes = MeetingMinutes(
            parts: [],
            decisions: [],
            actions: [
                .init(text: "- Share the schedule.", lines: [5]),
                .init(text: "Update the notes", lines: [2], owner: "Maria", due: "Wednesday"),
                .init(text: "update the notes!", lines: [2]),
                .init(text: "Something unsourced", lines: []),
            ],
            keyPoints: [.init(text: "None", lines: [1])],
            questions: []
        ).validated(entryCount: 9)
        #expect(minutes.actions.map(\.text) == ["Update the notes", "Share the schedule", "Something unsourced"])
        #expect(minutes.actions.first?.owner == "Maria")
        #expect(minutes.keyPoints.isEmpty)
    }

    @Test func aSentenceInSeveralListsStaysInTheFirstAndQuestionsCiteLittle() {
        let minutes = MeetingMinutes(
            parts: [],
            decisions: [.init(text: "Ship Monday", lines: [1])],
            actions: [.init(text: "Update the notes", lines: [2])],
            keyPoints: [.init(text: "Ship Monday", lines: [1]), .init(text: "Privacy matters", lines: [3])],
            questions: [.init(text: "Privacy matters", lines: [3]), .init(text: "Does it work offline", lines: [4]),
                        .init(text: "A stretch of talk", lines: [1, 2, 3, 4])]
        ).validated(entryCount: 5, template: .full)
        #expect(minutes.keyPoints.map(\.text) == ["Privacy matters"])
        #expect(minutes.questions.map(\.text) == ["Does it work offline"])
    }

    @Test func aNameBelongsToTasksOnly() {
        let minutes = MeetingMinutes(
            parts: [], decisions: [.init(text: "Ship Monday", lines: [1], owner: "Maria", due: "Monday")], actions: [],
            keyPoints: [.init(text: "Privacy matters", lines: [2], owner: "Speaker")], questions: []
        ).validated(entryCount: 3, template: .full)
        #expect(minutes.decisions.first?.owner == nil && minutes.decisions.first?.due == nil)
        #expect(minutes.keyPoints.first?.displayText == "Privacy matters")
    }

    @Test func aTaskIsWrittenInOneWay() {
        #expect(MeetingMinutes.Point(text: "update the release notes", lines: [], owner: "Maria", due: "Wednesday").displayText == "Maria — update the release notes (Wednesday)")
        #expect(MeetingMinutes.Point(text: "share the schedule", lines: [], due: "today").displayText == "share the schedule (today)")
        #expect(MeetingMinutes.Point(text: "share the schedule", lines: []).displayText == "share the schedule")
    }

    @Test func emptyOwnerAndDueAreDropped() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "Do it", lines: [1], owner: "none", due: "")]).validated(entryCount: 1)
        #expect(minutes.actions.first?.owner == nil && minutes.actions.first?.due == nil)
    }

    @Test func aLongMeetingKeepsThePointsOfEveryPart() {
        let many = (1...30).map { MeetingMinutes.Point(text: "point \($0)", lines: [$0]) }
        let parts = (0..<3).map { MeetingMinutes.Part(lines: ($0 * 10 + 1)...($0 * 10 + 10), summary: "part \($0)") }
        let minutes = MeetingMinutes(parts: parts, decisions: [], actions: many).validated(entryCount: 30, template: .meeting)
        #expect(minutes.actions.count == MinutesTemplate.meeting.limit(.actions) * 3)
    }

    @Test func eachSectionIsCappedByTheTemplate() {
        let many = (1...20).map { MeetingMinutes.Point(text: "point \($0)", lines: [$0]) }
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: many).validated(entryCount: 20, template: .meeting)
        #expect(minutes.actions.count == MinutesTemplate.meeting.limit(.actions))
    }
}

@Suite("Minutes prompt")
struct MinutesPromptTests {
    @Test func everySituationAndLanguageHasInstructions() {
        for scenario in Scenario.allCases {
            for language in SpokenLanguage.allCases {
                let text = MinutesPrompt.instructions(for: scenario.minutes, scenario: scenario, language: language)
                #expect(text.count > 100)
                for section in scenario.minutes.sections {
                    #expect(text.contains(section.rawValue), "\(scenario) \(language) \(section)")
                }
            }
        }
    }

    @Test func aSeminarIsNotToldToFindDecisionsOrTasks() {
        let text = MinutesPrompt.instructions(for: Scenario.seminar.minutes, scenario: .seminar, language: .english)
        #expect(!text.contains("decisions: only"))
        #expect(!text.contains("actions: what someone"))
        #expect(text.contains("Leave these empty: decisions, actions"))
    }

    @Test func theRoleDiffersPerSituation() {
        let roles = Set(Scenario.allCases.map { MinutesPrompt.instructions(for: $0.minutes, scenario: $0, language: .korean).split(separator: "\n").first.map(String.init) })
        #expect(roles.count == 3)
    }

    @Test func theTaskRulesAskForWhoAndWhen() {
        let text = MinutesPrompt.instructions(for: Scenario.meeting.minutes, scenario: .meeting, language: .english)
        #expect(text.contains("owner") && text.contains("due"))
        #expect(text.contains("A question, a proposal or something still being reviewed is not a decision"))
    }

    @Test func headingsExistForEverySection() {
        for language in SpokenLanguage.allCases {
            let all = MinutesTemplate.Section.allCases.map { MinutesMarkdown.heading($0, language: language) }
            #expect(Set(all).count == all.count)
        }
    }

    @Test func theNotesFollowTheTemplate() {
        let entries = (0..<3).map { ScriptEntry(offset: Double($0) * 10, text: "x") }
        let minutes = MeetingMinutes(parts: [.init(lines: 1...3, summary: "A talk.")], decisions: [.init(text: "Ignored", lines: [1])], actions: [], keyPoints: [.init(text: "The key idea", lines: [2])], questions: [.init(text: "Why now?", lines: [3])])
        let md = MinutesMarkdown.render(minutes, entries: entries, title: "T", language: .english, template: .seminar)
        #expect(md.contains("## Key points") && md.contains("- The key idea (lines [2] 00:00:10)"))
        #expect(md.contains("## Open questions") && md.contains("- Why now?"))
        #expect(!md.contains("## Decisions") && !md.contains("Ignored"))
    }
}

@Suite("Notes of a situation hide what it does not show")
struct HiddenSectionsTests {
    @Test func aHiddenListDoesNotRemoveAVisiblePoint() {
        // a seminar shows key points and questions only; the model also filled the decisions with the same sentence
        let minutes = MeetingMinutes(
            parts: [], decisions: [.init(text: "The model needs less data", lines: [1])], actions: [],
            keyPoints: [.init(text: "The model needs less data", lines: [1])], questions: []
        ).validated(entryCount: 2, template: .seminar)
        #expect(minutes.keyPoints.map(\.text) == ["The model needs less data"])
        #expect(minutes.decisions.isEmpty)
    }
}

@Suite("Task owners")
struct TaskOwnerTests {
    @Test func aRoleWordIsNotWhoWillDoIt() {
        for word in ["user", "User", "사용자", "화자", "ユーザー", "用户", "speaker"] {
            #expect(MinutesText.person(word) == nil, "\(word)")
        }
        #expect(MinutesText.person("Maria") == "Maria")
        #expect(MinutesText.person(" 민수 ") == "민수")
    }

    @Test func aTaskWithARoleWordKeepsNoOwner() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "Prepare the environment", lines: [2], owner: "사용자", due: "Friday")]).validated(entryCount: 3)
        #expect(minutes.actions.first?.displayText == "Prepare the environment (Friday)")
    }
}
