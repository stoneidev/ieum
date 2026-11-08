import Foundation
import CaptionCore

/// User choices that survive relaunch. Launch arguments such as `-meetingMode conversation` override them for a run.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    private static func value<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        T(rawValue: defaults.string(forKey: key) ?? "") ?? fallback
    }

    private static func flag(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    // MARK: Meeting

    static var meetingMode: MeetingMode {
        get { value("meetingMode", default: .englishToKorean) }
        set { defaults.set(newValue.rawValue, forKey: "meetingMode") }
    }
    /// The English variant recognized in English modes.
    static var englishVariant: Language {
        get {
            let stored: Language = value("englishVariant", default: .englishUS)
            return stored == .korean ? .englishUS : stored
        }
        set { defaults.set(newValue.rawValue, forKey: "englishVariant") }
    }
    /// The language for "captions only".
    static var captionLanguage: Language {
        get { value("captionLanguage", default: .englishUS) }
        set { defaults.set(newValue.rawValue, forKey: "captionLanguage") }
    }
    static var source: Source {
        get { value("source", default: .microphone) }
        set { defaults.set(newValue.rawValue, forKey: "source") }
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

    static var fadeWhenQuiet: Bool {
        get { flag("fadeWhenQuiet", default: true) }
        set { defaults.set(newValue, forKey: "fadeWhenQuiet") }
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
