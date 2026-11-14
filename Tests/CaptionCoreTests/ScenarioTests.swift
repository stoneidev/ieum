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
        // the point with no source line is dropped; the others follow the meeting
        #expect(minutes.actions.map(\.text) == ["Update the notes", "Share the schedule"])
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
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu", "ant", "bee", "cat", "dog"]
        let many = (1...30).map { MeetingMinutes.Point(text: "Send the \(words[$0 - 1]) report", lines: [$0]) }
        let parts = (0..<3).map { MeetingMinutes.Part(lines: ($0 * 10 + 1)...($0 * 10 + 10), summary: "part \($0)") }
        let minutes = MeetingMinutes(parts: parts, decisions: [], actions: many).validated(entryCount: 30, template: .meeting)
        #expect(minutes.actions.count == MinutesTemplate.meeting.limit(.actions) * 3)
    }

    @Test func eachSectionIsCappedByTheTemplate() {
        let names = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango"]
        let many = (1...20).map { MeetingMinutes.Point(text: "Send the \(names[$0 - 1]) report", lines: [$0]) }
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
        #expect(text.contains("NOT a decision: an option or proposal, an opinion, a question, something still under review or waiting for approval"))
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

@Suite("Grounding")
struct GroundingTests {
    private let entries = [
        ScriptEntry(offset: 0, text: "Priya, can you send the patch by Tuesday?"),
        ScriptEntry(offset: 10, text: "민수 씨가 금요일까지 환경을 준비해 주세요."),
    ]

    @Test func aNameAndADayThatWereNeverSaidAreDropped() {
        let english = [ScriptEntry(offset: 0, text: "Priya, can you send the patch by Tuesday?")]
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [
            .init(text: "Send the patch", lines: [1], owner: "Priya", due: "Tuesday"),
            .init(text: "Publish", lines: [1], owner: "Dana", due: "Friday"),
        ]).grounded(in: english)
        #expect(minutes.actions[0].owner == "Priya" && minutes.actions[0].due == "Tuesday")
        #expect(minutes.actions[1].owner == nil && minutes.actions[1].due == nil)
    }

    @Test func aNameWithAParticleIsStillFound() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "환경 준비", lines: [2], owner: "민수 씨", due: "금요일")]).grounded(in: entries)
        #expect(minutes.actions[0].owner == "민수 씨" && minutes.actions[0].due == "금요일")
    }

    @Test func aDayInAnotherLanguageThanTheTranscriptIsKept() {
        // English meeting, Korean notes: "Tuesday" is written "화요일"
        let english = [ScriptEntry(offset: 0, text: "Priya, can you send the patch by Tuesday?")]
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "패치 전달", lines: [1], owner: "Priya", due: "화요일")]).grounded(in: english)
        #expect(minutes.actions[0].due == "화요일")
    }

    @Test func aPhraseThatIsNotANameIsDropped() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "Send", lines: [1], owner: "누군가 말했다", due: nil)]).grounded(in: entries)
        #expect(minutes.actions[0].owner == nil)
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

@Suite("Task text")
struct TaskTextTests {
    @Test func theOwnerIsNotRepeatedInFrontOfTheAction() {
        #expect(MinutesText.withoutPerson("Priya will fix the login bug", "Priya") == "fix the login bug")
        #expect(MinutesText.withoutPerson("Dana should send the patch", "Dana") == "send the patch")
        #expect(MinutesText.withoutPerson("Priya가 패치를 보냅니다", "Priya") == "패치를 보냅니다")
        #expect(MinutesText.withoutPerson("민수 씨가 환경을 준비한다", "민수 씨") == "환경을 준비한다")
    }

    @Test func aTextThatDoesNotStartWithTheOwnerIsLeftAlone() {
        #expect(MinutesText.withoutPerson("Fix the login bug", "Dana") == "Fix the login bug")
        #expect(MinutesText.withoutPerson("Dana", "Dana") == "Dana")
    }

    @Test func aPointWithoutASourceLineIsDropped() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [], keyPoints: [], questions: [
            .init(text: "What is drift?", lines: []), .init(text: "How often should you retrain?", lines: [9]),
        ]).validated(entryCount: 10, template: .seminar)
        #expect(minutes.questions.map(\.text) == ["How often should you retrain?"])
    }
}

@Suite("Near duplicates and pending decisions")
struct PendingTests {
    @Test func aRestatedTaskIsNotAlsoADecision() {
        let minutes = MeetingMinutes(
            parts: [],
            decisions: [.init(text: "금요일까지 테스트 환경 준비", lines: [5])],
            actions: [.init(text: "테스트 환경 준비", lines: [5], owner: "민수", due: "금요일")]
        ).validated(entryCount: 6)
        #expect(minutes.decisions.isEmpty)
        #expect(minutes.actions.count == 1)
    }

    @Test func differentThingsAreNotNearDuplicates() {
        #expect(!MinutesText.nearDuplicates("Ship the beta on Monday", "Update the release notes by Wednesday"))
        // two real tasks that look alike are two tasks
        #expect(!MinutesText.nearDuplicates("Send the report to Dana", "Send the report to Tom"))
        #expect(!MinutesText.nearDuplicates("Book the room on Monday", "Book the room on Friday"))
        #expect(MinutesText.nearDuplicates("Update the notes", "update the notes!"))
        #expect(MinutesText.nearDuplicates("Update the release notes", "Update the release notes by Wednesday"))
    }

    @Test func aDecisionThatSaysItIsStillOpenBecomesAQuestion() {
        let minutes = MeetingMinutes(parts: [], decisions: [
            .init(text: "Ship Monday", lines: [3]),
            .init(text: "We cannot decide to hire a second SRE until finance responds", lines: [7]),
            .init(text: "일본어 지원 여부는 아직 결정되지 않음", lines: [10]),
        ], actions: []).validated(entryCount: 10)
        #expect(minutes.decisions.map(\.text) == ["Ship Monday"])
        #expect(minutes.questions.map(\.text).sorted() == ["We cannot decide to hire a second SRE until finance responds", "일본어 지원 여부는 아직 결정되지 않음"].sorted())
    }

    @Test func pendingMarkersInSeveralLanguages() {
        for text in ["not yet decided", "아직 결정되지 않음", "未定です", "尚未决定", "The date hasn't been decided"] { #expect(MinutesText.looksPending(text), "\(text)") }
        for text in ["Ship on Monday", "월요일에 출시", "金曜日に決定"] { #expect(!MinutesText.looksPending(text), "\(text)") }
    }
}

@Suite("Review fixes")
struct ReviewFixTests {
    @Test func theSameWordsForTwoPeopleAreTwoTasks() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [
            .init(text: "Send the report", lines: [1], owner: "Dana"),
            .init(text: "Send the report", lines: [2], owner: "Tom"),
        ]).validated(entryCount: 3)
        #expect(minutes.actions.map(\.owner) == ["Dana", "Tom"])
    }

    @Test func aPointWithoutASourceDoesNotHideALaterGoodOne() {
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [
            .init(text: "Send the report", lines: []),
            .init(text: "Send the report to Dana by Friday", lines: [5]),
        ]).validated(entryCount: 6)
        #expect(minutes.actions.map(\.text) == ["Send the report to Dana by Friday"])
    }

    @Test func aNameIsOnlyRemovedWhenItStandsAlone() {
        #expect(MinutesText.withoutPerson("Annual review of the budget", "Ann") == "Annual review of the budget")
        #expect(MinutesText.withoutPerson("Alert the team", "Al") == "Alert the team")
        #expect(MinutesText.withoutPerson("Dana's report", "Dana") == "Dana's report")
        #expect(MinutesText.withoutPerson("민수 이사에게 보고", "민수") == "민수 이사에게 보고")
        #expect(MinutesText.withoutPerson("민수 은행에 입금", "민수") == "민수 은행에 입금")
        #expect(MinutesText.withoutPerson("민수 가격 확인", "민수") == "민수 가격 확인")
        // and when it does stand alone it goes
        #expect(MinutesText.withoutPerson("Priya will fix the login bug", "Priya") == "fix the login bug")
        #expect(MinutesText.withoutPerson("Priya: send the patch", "Priya") == "send the patch")
        #expect(MinutesText.withoutPerson("민수 씨가 환경을 준비한다", "민수 씨") == "환경을 준비한다")
        #expect(MinutesText.withoutPerson("민수가 환경을 준비한다", "민수") == "환경을 준비한다")
    }

    @Test func aNameCalledNaIsAName() {
        #expect(MinutesText.person("Na") == "Na")
        #expect(MinutesText.person("none") == nil)
    }

    @Test func aDecisionToKeepSomethingOnHoldWordsIsNotPending() {
        #expect(!MinutesText.looksPending("Put the vendor contract on hold until Monday and keep the current plan"))
        #expect(!MinutesText.looksPending("미정산 금액은 월요일에 처리"))
        #expect(!MinutesText.looksPending("保留現行方針で進める"))
        #expect(MinutesText.looksPending("The date hasn\u{2019}t been decided"))
        #expect(!MinutesText.looksPending("We decided on the plan"))
        #expect(MinutesText.looksPending("Not decided yet"))
    }

    @Test func twoDatesAreTwoPoints() {
        #expect(!MinutesText.nearDuplicates("Move the deadline to 14 March for the vendor contract", "Move the deadline to 15 March for the vendor contract"))
        #expect(!MinutesText.nearDuplicates("Budget is 50", "Budget is 500k"))
        #expect(MinutesText.nearDuplicates("Move the deadline to 14 March", "move the deadline to 14 March!"))
    }

    @Test func groundingChecksWholeWords() {
        let english = [ScriptEntry(offset: 0, text: "Please do the job by Friday, and also call Dana Lee.")]
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [
            .init(text: "A", lines: [1], owner: "Jo"),          // only inside "job"
            .init(text: "B", lines: [1], owner: "Al"),          // only inside "also"
            .init(text: "C", lines: [1], owner: "Dana Lee"),
            .init(text: "D", lines: [1], owner: "Dana", due: "by Friday"),
        ]).grounded(in: english)
        #expect(minutes.actions.map(\.owner) == [nil, nil, "Dana Lee", "Dana"])
        #expect(minutes.actions[3].due == "by Friday")
    }

    @Test func aOneCharacterChineseNameIsFound() {
        let chinese = [ScriptEntry(offset: 0, text: "王，请周五前把请柬发出去。")]
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "发请柬", lines: [1], owner: "王", due: "周五")]).grounded(in: chinese)
        #expect(minutes.actions[0].owner == "王" && minutes.actions[0].due == "周五")
    }

    @Test func aLatinDayInNotesAboutAKoreanTranscriptIsInvented() {
        let korean = [ScriptEntry(offset: 0, text: "릴리스 노트는 제가 수요일에 공유하겠습니다.")]
        let minutes = MeetingMinutes(parts: [], decisions: [], actions: [.init(text: "릴리스 노트 공유", lines: [1], due: "Thursday")]).grounded(in: korean)
        #expect(minutes.actions[0].due == nil)
    }

    @Test func skippedLinesAreSaidInTheNotes() {
        let entries = (0..<4).map { ScriptEntry(offset: Double($0) * 10, text: "x") }
        let minutes = MeetingMinutes(parts: [.init(lines: 1...4, summary: "A talk.")], decisions: [], actions: [], unread: [3, 9]).validated(entryCount: 4, template: .seminar)
        #expect(minutes.unread == [3])
        let md = MinutesMarkdown.render(minutes, entries: entries, title: "T", language: .english, template: .seminar)
        #expect(md.contains("did not read these lines") && md.contains("[3]"))
        let korean = MinutesMarkdown.render(minutes, entries: entries, title: "T", language: .korean, template: .seminar)
        #expect(korean.contains("읽지 않은 줄") && korean.contains("[3]"))
    }
}
