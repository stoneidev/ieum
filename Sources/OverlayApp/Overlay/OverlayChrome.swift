import AppKit
import CaptionCore
import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let palette = Theme.palette(for: model.background)
        Group {
            switch model.displayMode {
            case .bar: SubtitleBarView(model: model, palette: palette)
            case .panel: TranscriptPanelView(model: model, palette: palette)
            }
        }
        .background { background(palette) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        }
        .preferredColorScheme(palette.scheme)
    }

    /// Only the background is translucent; text always stays fully opaque.
    @ViewBuilder
    private func background(_ palette: Theme.Palette) -> some View {
        switch model.background {
        case .glass, .light:
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(model.backgroundOpacity)
                palette.tint.opacity(model.backgroundOpacity)
            }
        case .solid, .black:
            palette.tint.opacity(model.backgroundOpacity)
        }
    }
}

/// A small tally light: amber and breathing while listening, red when something needs attention.
struct StatusDot: View {
    let status: SessionStatus
    let idleColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(status == .listening && dim ? 0.35 : 1)
            .animation(status == .listening && !reduceMotion ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: dim)
            .onAppear { dim = true }
            .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        switch status {
        case .listening: Theme.live
        case .starting: idleColor
        case .idle: idleColor.opacity(0.5)
        case .error: Theme.alert
        }
    }

    private var accessibilityText: String {
        switch status {
        case .listening: "Listening"
        case .starting: "Starting"
        case .idle: "Captions off"
        case .error: "Problem"
        }
    }
}

/// A small "Me" / "Them" tag for calls, where the microphone and the other side are recognized apart.
struct SpeakerChip: View {
    let speaker: Speaker
    let palette: Theme.Palette
    let size: CGFloat

    private var label: String { speaker == .me ? tr("Me", "나") : tr("Them", "상대") }

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.ink.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(palette.interim.opacity(speaker == .me ? 0.34 : 0.18)))
            .accessibilityLabel(speaker == .me ? tr("You", "나") : tr("The other side", "상대"))
    }
}

/// A small "EN" / "KO" tag that says which language a sentence was spoken in (used in conversation mode).
struct LanguageChip: View {
    let language: String
    let palette: Theme.Palette
    let size: CGFloat

    var body: some View {
        Text(language.uppercased())
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.ink.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(palette.interim.opacity(0.22)))
            .accessibilityLabel(SpokenLanguage(code: language)?.name ?? language.uppercased())
    }
}

/// The way to turn captions on from the overlay itself, with the shortcut when shortcuts are enabled.
struct StartCaptionsButton: View {
    @ObservedObject var model: AppModel
    let fontSize: CGFloat

    var body: some View {
        Button(action: { model.start() }) {
            HStack(spacing: 8) {
                Text(tr("Start captions", "자막 시작")).font(.system(size: fontSize, weight: .semibold))
                if model.globalShortcuts {
                    Text("⌃⌥S").font(.system(size: max(12, fontSize - 4), weight: .medium, design: .rounded)).opacity(0.6)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.live))
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Starts live captions", "실시간 자막을 시작합니다"))
    }
}

/// The menu-bar menu, inside the overlay. macOS hides status items when the menu bar is full (the left-most one goes first),
/// and then the menu would be out of reach; this keeps mode, settings and quit one click away.
///
/// It is a real `NSMenu` shown from an `NSButton`, built when it is clicked. A SwiftUI `Menu` is rebuilt whenever the view
/// around it updates, which in the transcript panel is every time a word is recognized, and that closed it under the pointer.
