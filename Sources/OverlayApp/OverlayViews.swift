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
            .accessibilityLabel(language == "ko" ? "Korean" : "English")
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
struct OverlayMenuButton: NSViewRepresentable {
    let model: AppModel
    let palette: Theme.Palette

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstClickButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: tr("Menu", "메뉴"))?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        button.setAccessibilityLabel(tr("Menu", "메뉴"))
        button.target = context.coordinator
        button.action = #selector(Coordinator.show(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.contentTintColor = NSColor(palette.interim)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? { CGSize(width: 24, height: 24) }

    /// A click on the overlay while another app is active opens the menu at once instead of only bringing the window forward.
    private final class FirstClickButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// A menu item that runs a closure.
    private final class ActionItem: NSMenuItem {
        private let handler: () -> Void

        init(_ title: String, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
            state = checked ? .on : .off
            isEnabled = enabled
        }

        required init(coder: NSCoder) { fatalError("not used") }

        @objc private func fire() { handler() }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model: AppModel
        init(model: AppModel) { self.model = model }

        @objc func show(_ sender: NSButton) {
            // Just below the button, whichever way the hosting view's y axis points.
            buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 2 : -2), in: sender)
        }

        private func buildMenu() -> NSMenu {
            let model = self.model
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(ActionItem(model.isRunning ? tr("Stop captions", "자막 중지") : tr("Start captions", "자막 시작")) { model.toggleRunning() })

            let modes = NSMenu()
            modes.autoenablesItems = false
            for mode in MeetingMode.allCases {
                modes.addItem(ActionItem(mode.title, checked: mode == model.meetingMode, enabled: mode.isAvailableOnThisMac) { model.setMeetingMode(mode) })
            }
            let modeItem = NSMenuItem(title: tr("Meeting mode", "회의 모드"), action: nil, keyEquivalent: "")
            modeItem.submenu = modes
            menu.addItem(modeItem)

            menu.addItem(ActionItem(model.displayMode == .bar ? tr("Show transcript panel", "기록 패널로 전환") : tr("Show subtitle bar", "자막 바로 전환")) { model.cycleDisplayMode() })
            menu.addItem(ActionItem(tr("Keep on top of other windows", "다른 창 위에 항상 표시"), checked: model.keepsOnTop) { model.setKeepsOnTop(!model.keepsOnTop) })
            if !model.keepsOnTop {
                menu.addItem(ActionItem(tr("Bring captions to the front", "자막을 앞으로 가져오기")) { model.bringOverlayToFront() })
            }
            menu.addItem(.separator())
            menu.addItem(ActionItem(tr("Settings…", "설정…")) { model.openSettings() })
            menu.addItem(ActionItem(tr("Check for updates…", "업데이트 확인…")) { model.checkForUpdates() })
            menu.addItem(ActionItem(tr("Permissions and setup…", "권한 및 설정 점검…")) { model.openSetup() })
            menu.addItem(.separator())
            menu.addItem(ActionItem(tr("Quit Ieum", "Ieum 종료")) { NSApp.terminate(nil) })
            return menu
        }
    }
}

/// One click between the subtitle bar and the transcript panel (⌃⌥D does the same). It sits on both, in the same corner.
struct DisplayToggleButton: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    /// Quieter on the live subtitle bar, where nothing should compete with the words.
    var subdued = false
    @State private var hovering = false

    var body: some View {
        let toPanel = model.displayMode == .bar
        let label = toPanel ? tr("Show the transcript panel", "기록 패널로 전환") : tr("Show the subtitle bar", "자막 바로 전환")
        Button(action: { model.cycleDisplayMode() }) {
            Image(systemName: toPanel ? "list.bullet.rectangle" : "captions.bubble")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.interim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.ink.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(subdued && !hovering ? 0.55 : 1)
        .onHover { hovering = $0 }
        .help(label + (model.globalShortcuts ? "  ⌃⌥D" : ""))
        .accessibilityLabel(label)
    }
}

// MARK: - Subtitle bar

/// Hangul is drawn smaller than Latin at the same point size so both read as equally large.
enum ScriptScale {
    static let hangul: CGFloat = 0.86
    static let hangulPanel: CGFloat = 0.92

    static func factor(for text: String, hangulScale: CGFloat = hangul) -> CGFloat {
        TextScript.hangulRatio(text) > 0.3 ? hangulScale : 1
    }
}

struct SubtitleBarView: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    /// What the bar says right now: `confirmed` in full contrast, `tentative` muted.
    private struct Caption {
        var confirmed = ""
        var tentative = ""
        var plain: String { confirmed + tentative }
    }

    var body: some View {
        if model.status == .idle {
            idleBar
        } else {
            liveBar
        }
    }

    /// Captions are off: one calm line with the way to turn them on, instead of an empty multi-line bar.
    private var idleBar: some View {
        let size = model.textSize.points
        let fontSize = max(15, (size * 0.6).rounded())
        return HStack(spacing: 14) {
            StatusDot(status: .idle, idleColor: palette.interim)
            Text(tr("Captions are off", "자막이 꺼져 있습니다"))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(palette.interim)
            Spacer(minLength: 12)
            StartCaptionsButton(model: model, fontSize: fontSize)
            DisplayToggleButton(model: model, palette: palette)
            OverlayMenuButton(model: model, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, BarMetrics.horizontalPadding)
        .padding(.vertical, BarMetrics.verticalPadding)
    }

    @ViewBuilder
    private var liveBar: some View {
        let size = model.textSize.points
        let caption = currentCaption
        // Line pitch is fixed by the chosen size, so the bar height never depends on the language. A smaller
        // Hangul font keeps the same pitch and simply gets more leading.
        let pitch = BarMetrics.fontLineHeight(size) + BarMetrics.lineSpacing(size)
        let fontSize = size * ScriptScale.factor(for: caption.plain)
        let textHeight = BarMetrics.textHeight(lines: model.barLines, size: size)
        VStack(alignment: .leading, spacing: BarMetrics.secondaryGap) {
            if model.showsSecondaryRow { secondaryRow(size: size) }
            HStack(alignment: .bottom, spacing: 16) {
                StatusDot(status: model.status, idleColor: palette.interim)
                    .padding(.bottom, max(0, (BarMetrics.fontLineHeight(fontSize) - 9) / 2))
                // The text block is as tall as its content up to the chosen number of lines, anchored at the
                // bottom and clipped at the top, so older lines scroll out whole and never half-cut.
                text(caption)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineSpacing(pitch - BarMetrics.fontLineHeight(fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: textHeight, alignment: .bottomLeading)
                    // A flexible frame grows to whatever space it is offered; pin it to its content height
                    // (capped at `textHeight`) so a short caption does not leave a gap under the original row.
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                    .animation(.easeOut(duration: 0.25), value: model.barFinalText)
                    .animation(.easeOut(duration: 0.25), value: model.barTranslation.confirmed)
                DisplayToggleButton(model: model, palette: palette, subdued: true)
            }
        }
        // The window is fixed-height; the original row and the text sit together at the bottom of it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, BarMetrics.horizontalPadding)
        .padding(.vertical, BarMetrics.verticalPadding)
    }

    private func text(_ caption: Caption) -> Text {
        let separator = caption.confirmed.isEmpty || caption.tentative.isEmpty ? "" : " "
        return Text(caption.confirmed).foregroundColor(palette.ink)
            + Text(separator + caption.tentative).foregroundColor(palette.interim)
    }

    /// The speaker's own words, small and quiet, so the translation stays the thing you read.
    /// When translation cannot run, this row says why instead.
    private func secondaryRow(size: CGFloat) -> some View {
        let shown = model.translationNotice == nil && !showsOriginalAsMain ? originalLine : ""
        let small = BarMetrics.secondarySize(size) * ScriptScale.factor(for: shown, hangulScale: 0.92)
        return HStack(spacing: 8) {
            if model.translationNotice == nil, model.meetingMode.isConversation, !originalLanguage.isEmpty {
                LanguageChip(language: originalLanguage, palette: palette, size: max(10, small - 4))
            }
            Group {
                if let notice = model.translationNotice {
                    Text(notice).foregroundStyle(Theme.alert)
                } else if !showsOriginalAsMain {
                    // The transcript arrives first: keep it readable from across the table, not just a caption of the caption.
                    Text(originalLine).foregroundStyle(palette.ink.opacity(0.74))
                }
            }
            .font(.system(size: small, weight: .regular))
            .lineLimit(1)
            .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, minHeight: BarMetrics.secondaryHeight(size) - BarMetrics.secondaryGap, alignment: .leading)
        .padding(.leading, 25)
    }

    /// The translation has not arrived yet, so the original is the large line (and not repeated in the small row).
    private var showsOriginalAsMain: Bool {
        model.status == .listening && model.translationActive && model.translationNotice == nil
            && model.barTranslation.confirmed.isEmpty && model.barTranslation.tentative.isEmpty
            && !originalLine.isEmpty
    }

    private var originalLanguage: String {
        model.partial.isEmpty ? (model.finalizedLines.last?.language ?? "") : model.partialLanguage
    }

    /// Newest words of the original: the sentence being spoken, else the last finished one.
    private var originalLine: String {
        model.partial.isEmpty ? model.barFinalText : model.partial
    }

    private var currentCaption: Caption {
        switch model.status {
        case .error(let message):
            return Caption(confirmed: message)
        case .idle:
            return Caption()
        case .starting:
            return Caption(tentative: tr("Starting…", "시작하는 중…"))
        case .listening where model.translationActive:
            let t = model.barTranslation
            if t.confirmed.isEmpty && t.tentative.isEmpty {
                // Nothing translated yet: show what was heard, muted, until its translation arrives.
                if showsOriginalAsMain { return Caption(tentative: originalLine) }
                return Caption(tentative: tr("Listening…", "듣는 중…"))
            }
            return Caption(confirmed: t.confirmed, tentative: t.tentative)
        case .listening:
            if model.barFinalText.isEmpty && model.partial.isEmpty { return Caption(tentative: tr("Listening…", "듣는 중…")) }
            return Caption(confirmed: model.barFinalText, tentative: model.barFinalText.isEmpty || model.partial.isEmpty ? model.partial : " " + model.partial)
        }
    }
}

// MARK: - Transcript panel

struct TranscriptPanelView: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Body text follows the chosen text size, but stays in a range that suits a scrolling list.
    private var bodySize: CGFloat { max(14, (model.textSize.points * 0.57).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.ink.opacity(0.10))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.finalizedLines.isEmpty && model.partial.isEmpty {
                            Text(emptyMessage)
                                .font(.system(size: bodySize - 2))
                                .foregroundStyle(palette.interim)
                                .padding(.top, 6)
                        }
                        ForEach(model.finalizedLines) { line in
                            // A line keeps its translation after captions stop; only lines that never got one show the original.
                            if let translation = line.displayTranslation {
                                row(
                                    time: Self.timeFormatter.string(from: line.time),
                                    text: translation,
                                    color: line.translation == nil ? palette.interim : palette.ink,
                                    original: model.translationLayout == .both ? line.text : nil,
                                    language: line.language
                                )
                            } else {
                                row(time: Self.timeFormatter.string(from: line.time), text: line.text, color: palette.ink, original: nil, language: line.language)
                            }
                        }
                        if !model.partial.isEmpty {
                            if model.translationActive, !model.translatedPartial.isEmpty {
                                row(time: "·  ·  ·", text: model.translatedPartial, color: palette.interim,
                                    original: model.translationLayout == .both ? model.partial : nil, language: model.partialLanguage)
                            } else {
                                row(time: "·  ·  ·", text: model.partial, color: palette.interim, original: nil, language: model.partialLanguage)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.finalizedLines.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.partial) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusDot(status: model.status, idleColor: palette.interim)
            // The controls on the right keep their size; the names give way (and are cut with an ellipsis) in a narrow panel.
            Text(model.meetingMode.shortTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .help(model.meetingMode.title)
            Image(systemName: model.source == .microphone ? "mic.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .help(model.source.title)
                .accessibilityLabel(model.source.title)
            Spacer(minLength: 8)
            if model.status == .idle {
                StartCaptionsButton(model: model, fontSize: 13)
            } else if model.status == .listening, model.translationNotice == nil {
                Button(action: { model.toggleRunning() }) {
                    HStack(spacing: 6) {
                        Text(tr("Stop", "중지")).font(.system(size: 13, weight: .medium))
                        if model.globalShortcuts {
                            Text("⌃⌥S").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.6)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(palette.ink.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint(tr("Stops live captions and saves the transcript", "실시간 자막을 멈추고 기록을 저장합니다"))
            } else if let notice = model.translationNotice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.alert)
                    .lineLimit(2)
            } else if case .error(let message) = model.status {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.alert)
                    .lineLimit(2)
            }
            DisplayToggleButton(model: model, palette: palette)
            OverlayMenuButton(model: model, palette: palette)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func row(time: String, text: String, color: Color, original: String?, language: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.system(size: max(11, (bodySize * 0.72).rounded()), weight: .regular).monospacedDigit())
                    .foregroundStyle(palette.interim)
                if model.meetingMode.isConversation, !language.isEmpty {
                    LanguageChip(language: language, palette: palette, size: 10)
                }
            }
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                // The language that was spoken comes first, its translation underneath.
                if let original {
                    Text(original)
                        .font(.system(size: max(12, bodySize - 4), weight: .regular))
                        .foregroundStyle(palette.interim)
                        .textSelection(.enabled)
                }
                Text(text)
                    .font(.system(size: bodySize * ScriptScale.factor(for: text, hangulScale: ScriptScale.hangulPanel), weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(color)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyMessage: String {
        model.isRunning
            ? tr("Listening. Sentences appear here as they are finished.", "듣고 있습니다. 문장이 끝나면 여기에 쌓입니다.")
            : tr("Captions are off. Finished sentences will be listed here with their time.", "자막이 꺼져 있습니다. 시작하면 끝난 문장이 시각과 함께 여기에 쌓입니다.")
    }
}

// MARK: - Settings preview

/// The subtitle bar as it will look with the current display settings, over a stand-in for a video call,
/// so size, lines and background can be judged without starting captions.
struct CaptionPreview: View {
    @ObservedObject var model: AppModel

    private static let layoutWidth: CGFloat = 760

    private var sample: (original: String, shown: String, secondary: Bool) {
        let english = "Starting next Monday. The budget is still under review, and we will confirm it by tomorrow. Let us share the schedule today."
        let korean = "다음 주 월요일부터 시작합니다. 예산은 아직 검토 중이며 내일까지 확정해서 알려드리겠습니다. 일정은 오늘 안에 공유하겠습니다."
        switch model.meetingMode {
        case .englishToKorean, .conversation: return (english, korean, model.translationLayout == .both)
        case .koreanToEnglish: return (korean, english, model.translationLayout == .both)
        case .koreanCaptions: return (korean, korean, false)
        case .englishCaptions: return (english, english, false)
        }
    }

    var body: some View {
        let palette = Theme.palette(for: model.background)
        let size = model.textSize.points
        let content = sample
        let fontSize = size * ScriptScale.factor(for: content.shown)
        let pitch = BarMetrics.fontLineHeight(size) + BarMetrics.lineSpacing(size)
        let barHeight = BarMetrics.height(lines: model.barLines, size: size, secondaryRow: content.secondary)
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.layoutWidth
            ZStack(alignment: .bottom) {
                backdrop
                VStack(alignment: .leading, spacing: BarMetrics.secondaryGap) {
                    if content.secondary {
                        Text(content.original)
                            .font(.system(size: BarMetrics.secondarySize(size) * ScriptScale.factor(for: content.original, hangulScale: 0.92)))
                            .foregroundStyle(palette.interim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 25)
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        StatusDot(status: .listening, idleColor: palette.interim)
                            .padding(.bottom, max(0, (BarMetrics.fontLineHeight(fontSize) - 9) / 2))
                        Text(content.shown)
                            .font(.system(size: fontSize, weight: .medium))
                            .lineSpacing(pitch - BarMetrics.fontLineHeight(fontSize))
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxHeight: BarMetrics.textHeight(lines: model.barLines, size: size), alignment: .bottomLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .clipped()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, BarMetrics.horizontalPadding)
                .padding(.vertical, BarMetrics.verticalPadding)
                .frame(width: Self.layoutWidth, height: barHeight)
                .background { barBackground(palette) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(palette.border, lineWidth: 0.5) }
                .preferredColorScheme(palette.scheme)
                .scaleEffect(scale, anchor: .bottom)
                .frame(width: geometry.size.width, height: barHeight * scale, alignment: .bottom)
                .padding(.bottom, 14)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Preview of the subtitle bar", "자막 바 미리보기"))
    }

    /// A stand-in for a video call behind the bar, so the effect of the opacity is visible.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.28, blue: 0.34), Color(red: 0.12, green: 0.14, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(index == 1 ? 0.16 : 0.09))
                        .overlay(Image(systemName: "person.fill").font(.system(size: 34)).foregroundStyle(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    private func barBackground(_ palette: Theme.Palette) -> some View {
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
