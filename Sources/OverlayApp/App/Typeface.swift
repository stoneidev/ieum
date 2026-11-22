import AppKit
import SwiftUI

/// The type used in the app's own windows (the What's new tour and the update window): Ieum Sans, a subset of Pretendard,
/// which keeps Hangul and Latin letters at one size and weight so mixed Korean/English lines read evenly. It is bundled in
/// Contents/Resources/Fonts (registered through ATSApplicationFontsPath); without it the system font is used.
enum Typeface {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "IeumSans-Bold"
        case .semibold, .medium: name = "IeumSans-SemiBold"
        default: name = "IeumSans-Regular"
        }
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
    }
}
