import CaptionCore
import Foundation

// Scores the meeting-notes prompt. Each fixture is a transcript with the facts that must come out (decisions, tasks with who and
// when, key points, open questions), what must NOT come out (a proposal or a pending matter written as a decision), and the line
// numbers the facts are said in. The notes are written by the real on-device model through the real code path (`MinutesWriter`).
//
//   swift run -c release minutes-eval Benchmarks/minutes            # every fixture
//   swift run -c release minutes-eval Benchmarks/minutes --runs 3   # repeat, to see the spread

struct Expectation: Decodable {
    var any: [String]                 // the fact is present when an item contains any of these (case-insensitive)
    var alsoAny: [String]?            // ... and also any of these (to tell "will not migrate" from "migrate")
    var lines: [Int]?                 // where it is said: the item should cite one of these lines
    var owner: [String]?              // tasks: the item's owner should contain one of these
    var due: [String]?                // tasks: the item's due should contain one of these
}

struct Fixture: Decodable {
    var name: String
    var scenario: String
    var language: String              // the language of the notes
    var transcript: [String]
    var decisions: [Expectation]?
    var tasks: [Expectation]?
    var keyPoints: [Expectation]?
    var questions: [Expectation]?
    var forbiddenDecisions: [[String]]?       // keyword groups that must not appear among the decisions
    var forbiddenTasks: [[String]]?
}

struct Score {
    var expected = 0, found = 0
    var cited = 0, citable = 0
    var ownerRight = 0, ownerChecked = 0
    var dueRight = 0, dueChecked = 0
    var forbidden = 0
    var items = 0, unlisted = 0
    var wrongLanguage = 0
    static func + (a: Score, b: Score) -> Score {
        Score(expected: a.expected + b.expected, found: a.found + b.found, cited: a.cited + b.cited, citable: a.citable + b.citable,
              ownerRight: a.ownerRight + b.ownerRight, ownerChecked: a.ownerChecked + b.ownerChecked,
              dueRight: a.dueRight + b.dueRight, dueChecked: a.dueChecked + b.dueChecked,
              forbidden: a.forbidden + b.forbidden, items: a.items + b.items, unlisted: a.unlisted + b.unlisted, wrongLanguage: a.wrongLanguage + b.wrongLanguage)
    }
}

func has(_ text: String, _ words: [String]) -> Bool {
    let lower = text.lowercased()
    return words.contains { lower.contains($0.lowercased()) }
}

func score(points: [MeetingMinutes.Point], expected: [Expectation], forbidden: [[String]], language: SpokenLanguage, verbose: Bool, label: String) -> Score {
    var result = Score()
    result.items = points.count
    var matched = Set<Int>()
    for want in expected {
        result.expected += 1
        guard let index = points.firstIndex(where: { point in has(point.text, want.any) && (want.alsoAny.map { has(point.text, $0) } ?? true) }) else {
            if verbose { print("    ✗ missing \(label): \(want.any.joined(separator: " | "))") }
            continue
        }
        matched.insert(index)
        result.found += 1
        let point = points[index]
        if let lines = want.lines {
            result.citable += 1
            if point.lines.contains(where: lines.contains) { result.cited += 1 } else if verbose { print("    ~ \(label) '\(point.text)' cites \(point.lines), expected one of \(lines)") }
        }
        if let owners = want.owner {
            result.ownerChecked += 1
            if let owner = point.owner, has(owner, owners) { result.ownerRight += 1 } else if verbose { print("    ~ \(label) '\(point.text)' owner '\(point.owner ?? "-")', expected \(owners)") }
        }
        if let dues = want.due {
            result.dueChecked += 1
            if let due = point.due, has(due, dues) { result.dueRight += 1 } else if verbose { print("    ~ \(label) '\(point.text)' due '\(point.due ?? "-")', expected \(dues)") }
        }
    }
    for point in points {
        if forbidden.contains(where: { has(point.text, $0) }) {
            result.forbidden += 1
            if verbose { print("    ✗ forbidden as \(label): \(point.text)") }
        }
        let script = language == .korean ? TextScript.hangulRatio(point.text) : (language == .english ? 1 - TextScript.cjkRatio(point.text) : 1)
        if script < 0.5 { result.wrongLanguage += 1 }
    }
    result.unlisted = points.indices.filter { !matched.contains($0) }.count
    return result
}

func percent(_ a: Int, _ b: Int) -> String { b == 0 ? "  -  " : String(format: "%4.0f%%", Double(a) / Double(b) * 100) }

@main
struct Main {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var runs = 1
        var verbose = true
        if let i = arguments.firstIndex(of: "--runs"), i + 1 < arguments.count { runs = Int(arguments[i + 1]) ?? 1; arguments.removeSubrange(i...(i + 1)) }
        if let i = arguments.firstIndex(of: "--quiet") { verbose = false; arguments.remove(at: i) }
        let directory = arguments.first ?? "Benchmarks/minutes"
        guard #available(macOS 26.0, *) else { print("needs macOS 26"); exit(1) }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        var total = Score()
        var rows: [(String, Score)] = []
        for file in files {
            guard let data = FileManager.default.contents(atPath: directory + "/" + file), let fixture = try? JSONDecoder().decode(Fixture.self, from: data),
                  let scenario = Scenario(rawValue: fixture.scenario), let language = SpokenLanguage(rawValue: fixture.language) else {
                print("cannot read \(file)"); continue
            }
            let entries = fixture.transcript.enumerated().map { ScriptEntry(offset: Double($0.offset) * 14, text: $0.element) }
            for run in 1...runs {
                if verbose { print("\n\(fixture.name) (run \(run))") }
                do {
                    let minutes = try await MinutesWriter.generate(entries: entries, language: language, scenario: scenario)
                    if verbose {
                        for part in minutes.parts { print("  summary: \(part.summary)") }
                        for (title, points) in [("decisions", minutes.decisions), ("tasks", minutes.actions), ("key points", minutes.keyPoints), ("questions", minutes.questions)] {
                            for point in points { print("  \(title): \(point.displayText)  \(point.lines)") }
                        }
                    }
                    var s = Score()
                    s = s + score(points: minutes.decisions, expected: fixture.decisions ?? [], forbidden: fixture.forbiddenDecisions ?? [], language: language, verbose: verbose, label: "decision")
                    s = s + score(points: minutes.actions, expected: fixture.tasks ?? [], forbidden: fixture.forbiddenTasks ?? [], language: language, verbose: verbose, label: "task")
                    s = s + score(points: minutes.keyPoints, expected: fixture.keyPoints ?? [], forbidden: [], language: language, verbose: verbose, label: "key point")
                    s = s + score(points: minutes.questions, expected: fixture.questions ?? [], forbidden: [], language: language, verbose: verbose, label: "question")
                    rows.append((fixture.name, s))
                    total = total + s
                } catch {
                    print("  failed: \(error)")
                    // A run that fails found nothing: it counts against the totals instead of vanishing from them.
                    var s = Score()
                    s.expected = (fixture.decisions?.count ?? 0) + (fixture.tasks?.count ?? 0) + (fixture.keyPoints?.count ?? 0) + (fixture.questions?.count ?? 0)
                    rows.append((fixture.name + " (FAILED)", s))
                    total = total + s
                }
            }
        }
        print("\n== \(directory): \(files.count) fixtures x \(runs) run(s) ==")
        print(String(format: "%-34@ %7@ %7@ %7@ %7@ %9@ %8@", "fixture" as NSString, "recall" as NSString, "cited" as NSString, "owner" as NSString, "due" as NSString, "forbidden" as NSString, "unlisted" as NSString))
        for (name, s) in rows {
            print(String(format: "%-34@ %7@ %7@ %7@ %7@ %9d %8d", name as NSString, percent(s.found, s.expected) as NSString, percent(s.cited, s.citable) as NSString,
                         percent(s.ownerRight, s.ownerChecked) as NSString, percent(s.dueRight, s.dueChecked) as NSString, s.forbidden, s.unlisted))
        }
        print(String(format: "%-34@ %7@ %7@ %7@ %7@ %9d %8d", "TOTAL" as NSString, percent(total.found, total.expected) as NSString, percent(total.cited, total.citable) as NSString,
                     percent(total.ownerRight, total.ownerChecked) as NSString, percent(total.dueRight, total.dueChecked) as NSString, total.forbidden, total.unlisted))
        print("  recall = expected facts found · cited = found facts that cite a line where they are said · owner/due = right person/day on tasks")
        print("  forbidden = pending matters or proposals written as decisions (lower is better) · unlisted = extra items not in the answer key · wrong-language items: \(total.wrongLanguage)")
    }
}
