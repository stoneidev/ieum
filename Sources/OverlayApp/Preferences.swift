import Foundation
import CaptionCore

/// User choices that survive relaunch. Launch arguments such as `-heardLanguage ja` override them for a run.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    private static func value<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        T(rawValue: defaults.string(forKey: key) ?? "") ?? fallback
    }

    private static func flag(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    // MARK: Meeting

    /// The languages of the meeting. Settings saved before languages could be chosen are carried over from the old "meetingMode".
    static var meetingSetup: MeetingSetup {
        get {
            guard let heard = defaults.string(forKey: "heardLanguage").flatMap(SpokenLanguage.init(rawValue:)) else {
                return MeetingSetup.migrated(mode: defaults.string(forKey: "meetingMode") ?? "", legacyCaptionLanguage: defaults.string(forKey: "captionLanguage"))
                    ?? MeetingSetup(heard: .english, shown: .korean)
            }
            return MeetingSetup(
                heard: heard, shown: defaults.string(forKey: "shownLanguage").flatMap(SpokenLanguage.init(rawValue:)),
                bothWays: defaults.bool(forKey: "bothWays")
            )
        }
        set {
            defaults.set(newValue.heard.rawValue, forKey: "heardLanguage")
            defaults.set(newValue.shown?.rawValue, forKey: "shownLanguage")
            defaults.set(newValue.bothWays, forKey: "bothWays")
        }
    }
    /// The English variant recognized in English modes.
    static var englishVariant: Language {
        get {
            let stored: Language = value("englishVariant", default: .englishUS)
            return stored == .korean ? .englishUS : stored
        }
        set { defaults.set(newValue.rawValue, forKey: "englishVariant") }
    }
    /// What the person is doing: a conversation, a meeting or a seminar. Settings saved before it existed get the closest one.
    static var scenario: Scenario {
        get {
            if let stored = defaults.string(forKey: "scenario").flatMap(Scenario.init(rawValue:)) { return stored }
            return Scenario.migrated(setup: meetingSetup, usesCall: source == .call, usesSystemAudio: source == .system)
        }
        set { defaults.set(newValue.rawValue, forKey: "scenario") }
    }
    /// The situation, written down the first time it is derived from older settings so that it does not change by itself
    /// when the person later changes the languages or the source.
    static func scenarioFixingMigration() -> Scenario {
        let value = scenario
        if defaults.string(forKey: "scenario") == nil { scenario = value }
        return value
    }
    /// How much Ieum has been used, counted on this Mac only, for the one friendly coffee ask.
    static var support: SupportState {
        get { defaults.data(forKey: "support").flatMap { try? JSONDecoder().decode(SupportState.self, from: $0) } ?? SupportState() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "support") }
    }
    static var source: Source {
        get { value("source", default: .microphone) }
        set { defaults.set(newValue.rawValue, forKey: "source") }
    }
    /// CoreAudio UID of the chosen microphone; nil follows the system default input.
    static var inputDeviceUID: String? {
        get { defaults.string(forKey: "inputDeviceUID") }
        set { defaults.set(newValue, forKey: "inputDeviceUID") }
    }
    static var vocabulary: [String] {
        get { defaults.stringArray(forKey: "vocabulary") ?? [] }
        set { defaults.set(newValue, forKey: "vocabulary") }
    }

    // MARK: Display

    static var displayMode: DisplayMode {
        get { value("displayMode", default: .bar) }
        set { defaults.set(newValue.rawValue, forKey: "displayMode") }
    }
    static let lineChoices = [1, 2, 3, 4]
    static var barLines: Int {
        get {
            let stored = defaults.integer(forKey: "barLines")
            return lineChoices.contains(stored) ? stored : 2
        }
        set { defaults.set(newValue, forKey: "barLines") }
    }
    static var textSize: TextSize {
        get { value("textSize", default: .medium) }
        set { defaults.set(newValue.rawValue, forKey: "textSize") }
    }
    static var background: BackgroundStyle {
        get { value("background", default: .glass) }
        set { defaults.set(newValue.rawValue, forKey: "background") }
    }
    static let opacityRange = 0.2...1.0
    static var backgroundOpacity: Double {
        get {
            guard defaults.object(forKey: "backgroundOpacity") != nil else { return 0.8 }
            return min(max(defaults.double(forKey: "backgroundOpacity"), opacityRange.lowerBound), opacityRange.upperBound)
        }
        set { defaults.set(newValue, forKey: "backgroundOpacity") }
    }
    static var translationLayout: TranslationLayout {
        get { value("translationLayout", default: .both) }
        set { defaults.set(newValue.rawValue, forKey: "translationLayout") }
    }

    // MARK: Behavior

    /// Show words from the second recognizer sooner (needs Speech Recognition permission).
    static var showsWordsSooner: Bool {
        get { flag("showsWordsSooner", default: true) }
        set { defaults.set(newValue, forKey: "showsWordsSooner") }
    }

    /// Keep the captions above every other window. Off: they behave like an ordinary window and can sit behind others.
    /// The app version whose "What's new" the person has seen (or that was current when they first installed it).
    static var lastSeenVersion: String? {
        get { defaults.string(forKey: "lastSeenVersion") }
        set { defaults.set(newValue, forKey: "lastSeenVersion") }
    }

    // MARK: Updates

    /// Ask the website once a day whether a newer version exists (and offer it).
    static var autoCheckUpdates: Bool {
        get { flag("autoCheckUpdates", default: true) }
        set { defaults.set(newValue, forKey: "autoCheckUpdates") }
    }
    static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }
    /// A version the person chose to skip.
    static var skippedUpdateVersion: String? {
        get { defaults.string(forKey: "skippedUpdateVersion") }
        set { defaults.set(newValue, forKey: "skippedUpdateVersion") }
    }
    /// For testing: read the update feed from this address instead of the website (`-updateFeedURL http://localhost:8765/latest.json`).
    /// For testing: pretend to be this version when comparing with the feed (`-updateCurrentVersion 0.0.1`).
    static var updateCurrentVersionOverride: String? { defaults.string(forKey: "updateCurrentVersion") }

    static var updateFeedOverride: URL? {
        defaults.string(forKey: "updateFeedURL").flatMap(URL.init(string:))
    }

    static var keepsOnTop: Bool {
        get { flag("keepsOnTop", default: true) }
        set { defaults.set(newValue, forKey: "keepsOnTop") }
    }

    /// Keeps the captions out of what screen sharing and screen recording send to other people.
    static var hidesFromSharing: Bool {
        get { flag("hidesFromSharing", default: true) }
        set { defaults.set(newValue, forKey: "hidesFromSharing") }
    }
    static var pointerAvoidance: PointerAvoidance {
        get { value("pointerAvoidance", default: PointerAvoidance.fade) }
        set { defaults.set(newValue.rawValue, forKey: "pointerAvoidance") }
    }
    static var clickThrough: Bool {
        get { flag("clickThrough", default: false) }
        set { defaults.set(newValue, forKey: "clickThrough") }
    }
    static var globalShortcuts: Bool {
        get { flag("globalShortcuts", default: true) }
        set { defaults.set(newValue, forKey: "globalShortcuts") }
    }
    static var uiLanguage: String {
        get { defaults.string(forKey: "uiLanguage") ?? "system" }
        set { defaults.set(newValue, forKey: "uiLanguage") }
    }
    static var autoStart: Bool { defaults.bool(forKey: "autoStart") }
    /// Remembers that the screen-recording prompt was shown, to tell "refused" from "never asked".
    static var didRequestScreenAccess: Bool {
        get { defaults.bool(forKey: "didRequestScreenAccess") }
        set { defaults.set(newValue, forKey: "didRequestScreenAccess") }
    }
    static var didShowSetup: Bool {
        get { defaults.bool(forKey: "didShowSetup") }
        set { defaults.set(newValue, forKey: "didShowSetup") }
    }

    static var scriptDirectory: URL {
        get {
            if let path = defaults.string(forKey: "scriptDirectory"), !path.isEmpty { return URL(fileURLWithPath: path) }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documents.appendingPathComponent("Ieum Transcripts", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "scriptDirectory") }
    }
}
