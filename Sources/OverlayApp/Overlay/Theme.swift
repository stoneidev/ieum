import AppKit
import CaptionCore
import SwiftUI

/// Design tokens. Smoked glass so the captions hold contrast over any content; one amber "live" signal;
/// interim words are muted until the recognizer commits them ("wet ink").
enum Theme {
    static let live = Color(red: 1.0, green: 0.698, blue: 0.141)         // #FFB224
    static let alert = Color(red: 1.0, green: 0.420, blue: 0.357)        // #FF6B5B
    static let corner: CGFloat = 20

    struct Palette {
        let ink: Color
        let interim: Color
        let tint: Color
        let border: Color
        let scheme: ColorScheme
    }

    /// Text colors follow the background, so contrast holds on both dark and light styles.
    static func palette(for style: BackgroundStyle) -> Palette {
        switch style {
        case .glass, .solid:
            return Palette(
                ink: Color(red: 0.957, green: 0.949, blue: 0.933),       // #F4F2EE
                interim: Color(red: 0.612, green: 0.639, blue: 0.671),   // #9CA3AB
                tint: Color(red: 0.082, green: 0.094, blue: 0.106),      // #15181B
                border: Color.white.opacity(0.10),
                scheme: .dark
            )
        case .black:
            // Pure black behind pure white: the highest contrast, and see-through when the opacity is lowered.
            return Palette(
                ink: .white,
                interim: Color(red: 0.690, green: 0.718, blue: 0.753),   // #B0B7C0
                tint: .black,
                border: Color.white.opacity(0.14),
                scheme: .dark
            )
        case .light:
            return Palette(
                ink: Color(red: 0.082, green: 0.094, blue: 0.106),       // #15181B
                interim: Color(red: 0.369, green: 0.400, blue: 0.439),   // #5E6670
                tint: Color(red: 0.957, green: 0.949, blue: 0.933),      // #F4F2EE
                border: Color.black.opacity(0.12),
                scheme: .light
            )
        }
    }
}

/// Subtitle-bar geometry derived from the chosen text size and line count, so the bar is exactly as tall as
/// its lines and never shows a half-cut line.
enum BarMetrics {
    static let verticalPadding: CGFloat = 18
    static let horizontalPadding: CGFloat = 30

    static func lineSpacing(_ size: CGFloat) -> CGFloat { (size * 0.15).rounded() }

    static func fontLineHeight(_ size: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: size, weight: .medium))
    }

    static func textHeight(lines: Int, size: CGFloat) -> CGFloat {
        let count = CGFloat(lines)
        return ceil(count * fontLineHeight(size) + (count - 1) * lineSpacing(size))
    }

    /// The small original-language row shown above the translation.
    static func secondarySize(_ size: CGFloat) -> CGFloat { max(15, (size * 0.62).rounded()) }
    static let secondaryGap: CGFloat = 6

    static func secondaryHeight(_ size: CGFloat) -> CGFloat {
        ceil(fontLineHeight(secondarySize(size))) + secondaryGap
    }

    static func height(lines: Int, size: CGFloat, secondaryRow: Bool = false) -> CGFloat {
        textHeight(lines: lines, size: size) + (secondaryRow ? secondaryHeight(size) : 0) + 2 * verticalPadding
    }

    /// While captions are off the bar is a single line with a Start button.
    static func idleHeight(size: CGFloat) -> CGFloat { height(lines: 1, size: size) }
}

/// Hangul is drawn smaller than Latin at the same point size so both read as equally large.
enum ScriptScale {
    static let hangul: CGFloat = 0.86
    static let hangulPanel: CGFloat = 0.92

    static func factor(for text: String, hangulScale: CGFloat = hangul) -> CGFloat {
        TextScript.cjkRatio(text) > 0.3 ? hangulScale : 1
    }
}
