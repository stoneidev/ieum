import Foundation

/// An app people hold meetings in. Ieum notices when one comes to the front and offers to start the captions, because the
/// usual mistake is starting them a few minutes late.
public struct MeetingApp: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum MeetingApps {
    public static let known: [MeetingApp] = [
        MeetingApp(bundleID: "us.zoom.xos", name: "Zoom"),
        MeetingApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        MeetingApp(bundleID: "com.microsoft.teams", name: "Microsoft Teams"),
        MeetingApp(bundleID: "com.cisco.webexmeetingsapp", name: "Webex"),
        MeetingApp(bundleID: "Cisco-Systems.Spark", name: "Webex"),
        MeetingApp(bundleID: "com.apple.FaceTime", name: "FaceTime"),
        MeetingApp(bundleID: "com.skype.skype", name: "Skype"),
    ]

    public static func app(forBundleID id: String?) -> MeetingApp? {
        guard let id else { return nil }
        return known.first { $0.bundleID == id }
    }
}

/// When to offer the captions. Once per app for a good while (switching back and forth between a call and a document must not
/// nag), never while they already run, and never for an app the person said no to.
public struct StartSuggestionPolicy: Sendable {
    public var cooldown: TimeInterval = 30 * 60
    private var lastOffered: [String: Date] = [:]
    public private(set) var muted: Set<String>

    public init(muted: Set<String> = []) { self.muted = muted }

    /// Records the offer when it returns true.
    public mutating func shouldOffer(for app: MeetingApp, now: Date, captionsRunning: Bool, enabled: Bool) -> Bool {
        guard enabled, !captionsRunning, !muted.contains(app.name) else { return false }
        if let last = lastOffered[app.name], now.timeIntervalSince(last) < cooldown { return false }
        lastOffered[app.name] = now
        return true
    }

    /// "Don't ask for this app": by name, so Teams old and new count as one.
    public mutating func mute(_ app: MeetingApp) { muted.insert(app.name) }

    public mutating func unmuteAll() { muted = [] }
}
