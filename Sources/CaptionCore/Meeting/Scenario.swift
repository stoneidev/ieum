import Foundation

/// What the person is doing with Ieum. The situation decides which choices make sense (a seminar is only listened to, so
/// there is no "both sides speak"), what the defaults are, and what the notes of the meeting look like.
public enum Scenario: String, CaseIterable, Sendable {
    /// Two people talking, usually face to face.
    case conversation
    /// Several people, often on a video call.
    case meeting
    /// A talk or lecture that is only listened to.
    case seminar

    /// Both sides speaking (the language is detected per sentence) only makes sense when people answer each other.
    public var allowsBothWays: Bool { self != .seminar }
    public var defaultsToBothWays: Bool { self == .conversation }

    /// The call source (microphone and system audio, each side in its own language) is for video meetings.
    public var allowsCall: Bool { self == .meeting }
    /// A conversation is in the room; the system audio is for what plays on this Mac.
    public var allowsSystemAudio: Bool { self != .conversation }
    /// Where the sound comes from when the situation is first chosen: a video meeting plays on this Mac, a talk or a
    /// conversation is heard by the microphone.
    public var prefersSystemAudio: Bool { self == .meeting }

    /// What the notes of this situation contain.
    public var minutes: MinutesTemplate { MinutesTemplate.template(for: self) }

    /// The language setup this situation starts from: both sides speaking on for a conversation, off for the others.
    public func defaultSetup(from setup: MeetingSetup, bothWaysAvailable: Bool) -> MeetingSetup {
        let wanted = defaultsToBothWays && bothWaysAvailable && setup.translates
        return setup.speakingBothWays(wanted)
    }

    /// The situation for settings saved before it existed: a call or system audio is a meeting (a conversation is in the
    /// room), people answering each other at the microphone is a conversation, anything else a meeting.
    public static func migrated(setup: MeetingSetup, usesCall: Bool, usesSystemAudio: Bool = false) -> Scenario {
        if usesCall || usesSystemAudio { return .meeting }
        return setup.bothWays ? .conversation : .meeting
    }
}
