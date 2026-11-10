import Foundation

/// What the update feed (`latest.json` on the website) says about the newest release.
public struct UpdateFeed: Codable, Sendable, Equatable {
    public var version: String
    public var url: URL
    /// SHA-256 of the disk image, lowercase hex.
    public var sha256: String
    public var size: Int?
    /// Lowest macOS that runs this version, such as "14.0".
    public var minimumMacOS: String?
    /// Release notes by language code ("en", "ko"), one entry per line.
    public var notes: [String: [String]]?
    public var published: String?

    public init(version: String, url: URL, sha256: String, size: Int? = nil, minimumMacOS: String? = nil, notes: [String: [String]]? = nil, published: String? = nil) {
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.minimumMacOS = minimumMacOS
        self.notes = notes
        self.published = published
    }
}

/// The decisions around an update check, kept free of any networking so they can be tested.
public enum UpdateCheck {
    public enum Outcome: Equatable, Sendable {
        case upToDate
        /// A newer version the person has already declined; shown again only when they ask.
        case skipped(UpdateFeed)
        case available(UpdateFeed)
        case needsNewerMacOS(UpdateFeed, required: String)
        /// The feed cannot be trusted or read (bad version, address or checksum).
        case invalid
    }

    /// Hosts a release download may come from. A feed pointing anywhere else is refused, whatever it says.
    static let allowedHosts: Set<String> = ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    /// - Parameters:
    ///   - skipped: a version the person chose to skip.
    ///   - userInitiated: "Check for updates" pressed by hand: a skipped version is offered again.
    ///   - allowLocalHost: for tests against a local feed only.
    public static func evaluate(
        feed: UpdateFeed, current: String, skipped: String?, macOS: String, userInitiated: Bool, allowLocalHost: Bool = false
    ) -> Outcome {
        guard let offered = AppVersion(feed.version), let running = AppVersion(current),
              isValidDownload(feed.url, allowLocalHost: allowLocalHost), isSHA256(feed.sha256)
        else { return .invalid }
        guard offered > running else { return .upToDate }
        if let minimum = feed.minimumMacOS, let needed = AppVersion(minimum), let have = AppVersion(macOS), have < needed {
            return .needsNewerMacOS(feed, required: minimum)
        }
        if !userInitiated, let skipped, let skippedVersion = AppVersion(skipped), skippedVersion == offered { return .skipped(feed) }
        return .available(feed)
    }

    /// Whether a check is due: never checked, or the last one was at least `interval` ago.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = 24 * 3600) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
    }

    public static func isValidDownload(_ url: URL, allowLocalHost: Bool = false) -> Bool {
        if allowLocalHost, let host = url.host, host == "localhost" || host == "127.0.0.1" { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    public static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// The notes in the person's language, falling back to English.
    public static func notes(of feed: UpdateFeed, language: String) -> [String] {
        feed.notes?[language] ?? feed.notes?["en"] ?? []
    }
}
