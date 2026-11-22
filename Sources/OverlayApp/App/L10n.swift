import Foundation

/// UI language. The default follows the system; Settings can force Korean or English.
@MainActor
enum L10n {
    static var choice: String = Preferences.uiLanguage

    static var isKorean: Bool {
        switch choice {
        case "ko": true
        case "en": false
        default: Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }
}

/// English and Korean text side by side, so a missing translation is visible at the call site.
@MainActor
func tr(_ english: String, _ korean: String) -> String {
    L10n.isKorean ? korean : english
}
