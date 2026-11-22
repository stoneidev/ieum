import Foundation

/// When to ask, once, whether Ieum has earned a coffee. Everything is counted on this Mac only (no request is made), and the
/// ask comes after a finished meeting, never during one: first when the person has used Ieum for a few meetings, then rarely.
public struct SupportState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Still open to being asked.
        case active
        /// Said yes (opened the page). Never asked again.
        case supporter
        /// Said "no thanks" or turned the reminder off. Never asked again.
        case muted
    }

    /// Meetings that were used for real (a few sentences were captioned), and how many sentences they held.
    public var meetings = 0
    public var sentences = 0
    /// How many times the ask has been shown.
    public var asked = 0
    public var status: Status = .active

    public init(meetings: Int = 0, sentences: Int = 0, asked: Int = 0, status: Status = .active) {
        self.meetings = meetings
        self.sentences = sentences
        self.asked = asked
        self.status = status
    }

    /// A meeting that captioned fewer sentences than this was a test, a mistake or a quick look, and does not count.
    public static let minimumSentences = 3
    /// The meeting after which the first, second and third ask come. The last ask is the last.
    public static let thresholds = [3, 12, 30]

    /// Counts a finished meeting. Returns the ask to show now, if one is due.
    @discardableResult
    public mutating func finishedMeeting(sentences count: Int) -> Int? {
        guard count >= Self.minimumSentences else { return nil }
        meetings += 1
        sentences += count
        guard status == .active, asked < Self.thresholds.count, meetings >= Self.thresholds[asked] else { return nil }
        let stage = asked
        asked += 1
        return stage
    }

    /// "No thanks", or the reminder switched off.
    public mutating func declined() { if status == .active { status = .muted } }
    /// The page was opened.
    public mutating func supported() { status = .supporter }
    /// The reminder switched on again. A supporter stays a supporter.
    /// Switching it on again means one more ask is wanted, even if all three were used up.
    public mutating func reminded() {
        guard status == .muted else { return }
        status = .active
        asked = min(asked, Self.thresholds.count - 1)
    }

    public var asksAgain: Bool { status == .active && asked < Self.thresholds.count }
}
