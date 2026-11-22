import AppKit
import CaptionCore
import SwiftUI

/// A small pill that opens a menu: how the situation and the languages are chosen where they are used (on the bar and the
/// panel), not deep in the settings.
struct PillMenuButton: NSViewRepresentable {
    let title: String
    let palette: Theme.Palette
    var fontSize: CGFloat = 13
    let tip: String
    let accessibility: String
    let makeMenu: @MainActor () -> NSMenu

    func makeCoordinator() -> Coordinator { Coordinator(makeMenu: makeMenu) }

    func makeNSView(context: Context) -> NSButton {
        let button = ChipButton()
        button.isBordered = false
        button.wantsLayer = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.show(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setAccessibilityRole(.popUpButton)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        let ink = NSColor(palette.ink)
        let text = NSMutableAttributedString(string: title + " ", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: ink,
        ])
        text.append(NSAttributedString(string: "▾", attributes: [.font: NSFont.systemFont(ofSize: fontSize - 2), .foregroundColor: ink.withAlphaComponent(0.7)]))
        button.attributedTitle = text
        button.layer?.cornerRadius = (fontSize + 10) / 2
        button.layer?.backgroundColor = NSColor(palette.interim).withAlphaComponent(0.20).cgColor
        button.toolTip = tip
        button.setAccessibilityLabel(accessibility)
        context.coordinator.makeMenu = makeMenu
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let size = nsView.attributedTitle.size()
        return CGSize(width: ceil(size.width) + 22, height: fontSize + 10)
    }

    private final class ChipButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    }

    @MainActor
    final class Coordinator: NSObject {
        var makeMenu: @MainActor () -> NSMenu
        init(makeMenu: @escaping @MainActor () -> NSMenu) { self.makeMenu = makeMenu }

        @objc func show(_ sender: NSButton) {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 2 : -2), in: sender)
        }
    }
}

/// A menu item that runs a closure.
final class PillMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

private func heading(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
}

/// The situation (conversation, meeting, seminar).
struct SituationChip: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    var fontSize: CGFloat = 13

    var body: some View {
        PillMenuButton(
            title: model.scenario.chipTitle, palette: palette, fontSize: fontSize,
            tip: tr("What are you doing? ", "지금 무엇을 하시나요? ") + model.scenario.hint,
            accessibility: tr("Situation: ", "상황: ") + model.scenario.title,
            makeMenu: { [model] in
                let menu = NSMenu()
                menu.autoenablesItems = false
                menu.addItem(heading(tr("What are you doing?", "지금 무엇을 하시나요?")))
                for scenario in Scenario.allCases {
                    menu.addItem(PillMenuItem(scenario.title + "  ·  " + scenario.hint, checked: scenario == model.scenario, symbol: scenario.symbol) { model.setScenario(scenario) })
                }
                return menu
            }
        )
    }
}

/// The languages in one pill: "English → 한국어" (translated) or "English · captions only". The menu is the whole choice:
/// the usual routes in one click, captions in one language, and the two-step choice for anything else.
struct LanguageRouteChip: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    var fontSize: CGFloat = 13
    /// Language codes instead of names, for a header with little room.
    var compact = false

    static func title(of setup: MeetingSetup, compact: Bool = false) -> String {
        func name(_ language: SpokenLanguage) -> String { compact ? language.code.uppercased() : language.nativeName }
        guard let shown = setup.shown else { return name(setup.heard) + " · " + tr("captions only", "자막만") }
        return "\(name(setup.heard)) \(setup.bothWays ? "↔" : "→") \(name(shown))"
    }

    var body: some View {
        PillMenuButton(
            title: Self.title(of: model.activeSetup, compact: compact), palette: palette, fontSize: fontSize,
            tip: model.activeSetup.explanation,
            accessibility: tr("Languages: ", "언어: ") + Self.title(of: model.activeSetup),
            makeMenu: { [model] in Self.menu(for: model) }
        )
    }

    @MainActor
    static func menu(for model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let setup = model.setup
        let mine = model.myLanguage
        menu.addItem(heading(tr("Translate what you hear", "들리는 말을 번역")))
        // the routes most people want, one click each: hear another language and read mine, or the other way round
        for other in SpokenLanguage.allCases where other != mine {
            menu.addItem(PillMenuItem("\(other.nativeName) → \(mine.nativeName)", checked: setup.translates && setup.heard == other && setup.shown == mine) {
                model.setRoute(heard: other, shown: mine)
            })
        }
        for other in SpokenLanguage.allCases where other != mine {
            menu.addItem(PillMenuItem("\(mine.nativeName) → \(other.nativeName)", checked: setup.translates && setup.heard == mine && setup.shown == other) {
                model.setRoute(heard: mine, shown: other)
            })
        }
        menu.addItem(.separator())
        menu.addItem(heading(tr("Captions only, no translation", "자막만 (번역 없음)")))
        for language in SpokenLanguage.allCases {
            menu.addItem(PillMenuItem(language.nativeName, checked: !setup.translates && setup.heard == language) { model.setRoute(heard: language, shown: nil) })
        }
        menu.addItem(.separator())
        // any other pair: the two-step choice
        let other = NSMenuItem(title: tr("Another pair of languages", "다른 언어 조합"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(heading(tr("Language you hear", "듣는 언어")))
        for language in SpokenLanguage.allCases {
            sub.addItem(PillMenuItem(language.nativeName, checked: setup.heard == language) { model.setHeard(language) })
        }
        sub.addItem(.separator())
        sub.addItem(heading(tr("Language you read", "보는 언어")))
        for language in SpokenLanguage.allCases {
            sub.addItem(PillMenuItem(language.nativeName, checked: setup.shown == language) { model.setShown(language) })
        }
        other.submenu = sub
        menu.addItem(other)
        if setup.translates {
            menu.addItem(PillMenuItem(tr("Swap languages", "언어 바꾸기")) { model.swapDirection() })
            if model.scenario.allowsBothWays {
                menu.addItem(PillMenuItem(tr("Both sides speak (detect the language)", "서로 번갈아 말함 (언어 자동 인식)"), checked: setup.bothWays,
                                          enabled: MeetingSetup.bothWaysIsAvailableOnThisMac) { model.setBothWays(!setup.bothWays) })
            }
        }
        return menu
    }
}

/// Where the sound comes from: the choices the situation offers, then the microphone when one is used. One place for the pill,
/// the ⋯ menu and the menu bar.
@MainActor
enum SourceMenu {
    /// The sources worth showing: what the situation offers on this Mac, and the current one even if it is not offered.
    static func choices(for model: AppModel) -> [Source] {
        Source.allCases.filter { $0.isAvailableOnThisMac && (model.scenario.allowedSources.contains($0) || $0 == model.source) }
    }

    /// The name of the microphone in use, for the pill.
    static func microphoneName(for model: AppModel, devices: [InputDevice] = InputDevices.available()) -> String {
        guard let uid = model.inputDeviceUID else { return tr("System default", "시스템 기본값") }
        return devices.first { $0.uid == uid }?.name ?? tr("Not connected (using the default)", "연결 안 됨 (기본값 사용)")
    }

    static func items(for model: AppModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = [heading(tr("Where does the sound come from?", "소리는 어디서 나나요?"))]
        for source in choices(for: model) {
            items.append(PillMenuItem(source.title, checked: source == model.source, symbol: source.symbol) { model.setSource(source) })
        }
        if model.source != .system {
            let devices = InputDevices.available()
            items.append(.separator())
            items.append(heading(tr("Microphone", "마이크")))
            items.append(PillMenuItem(tr("System default", "시스템 기본값"), checked: model.inputDeviceUID == nil) { model.setInputDevice(nil) })
            for device in devices {
                items.append(PillMenuItem(device.name, checked: model.inputDeviceUID == device.uid) { model.setInputDevice(device.uid) })
            }
            // A saved microphone that is not plugged in stays visible so the choice is not lost silently.
            if let saved = model.inputDeviceUID, !devices.contains(where: { $0.uid == saved }) {
                items.append(PillMenuItem(tr("Not connected (using the default)", "연결 안 됨 (기본값 사용)"), checked: true) { model.setInputDevice(saved) })
            }
        }
        return items
    }

    static func menu(for model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(for: model).forEach(menu.addItem)
        return menu
    }

    /// For the ⋯ menu and the menu bar: the same choices one level down.
    static func submenuItem(for model: AppModel) -> NSMenuItem {
        let item = NSMenuItem(title: tr("Audio source: ", "소리 입력: ") + model.source.shortTitle, action: nil, keyEquivalent: "")
        item.submenu = menu(for: model)
        return item
    }
}

/// The sound source in one pill, with the microphone beside it when one is used.
struct SourceChip: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    var fontSize: CGFloat = 13

    var body: some View {
        PillMenuButton(
            title: model.source.shortTitle, palette: palette, fontSize: fontSize,
            tip: model.source.hint,
            accessibility: tr("Audio source: ", "소리 입력: ") + model.source.title,
            makeMenu: { [model] in SourceMenu.menu(for: model) }
        )
    }
}

/// Before the captions start, the three situations as tiles in the empty panel: the choice that shapes everything else.
struct SituationPicker: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("What are you doing?", "지금 무엇을 하시나요?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
            ForEach(Scenario.allCases, id: \.self) { scenario in
                tile(scenario)
            }
            Text(model.scenario.explanation)
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .fixedSize(horizontal: false, vertical: true)
            languages
            sounds
            VocabularyTip(model: model, palette: palette)
                .padding(.top, 6)
        }
    }

    /// Translate, or only show captions in one language: the second thing to decide before starting, with the languages beside it.
    private var languages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Translate it?", "번역이 필요한가요?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
            HStack(spacing: 8) {
                choice(tr("Translate", "번역하기"), symbol: "character.bubble", selected: model.setup.translates) { model.setTranslates(true) }
                choice(tr("Captions only", "자막만"), symbol: "captions.bubble", selected: !model.setup.translates) { model.setTranslates(false) }
            }
            HStack(spacing: 8) {
                Text(model.setup.translates ? tr("Hear → read", "듣는 언어 → 보는 언어") : tr("Spoken language", "말하는 언어"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.interim)
                LanguageRouteChip(model: model, palette: palette)
            }
        }
    }

    /// Where the sound comes from: the choices of this situation as buttons, one line of what the chosen one does, and the microphone.
    private var sounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Where does the sound come from?", "소리는 어디서 나나요?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
            HStack(spacing: 8) {
                ForEach(SourceMenu.choices(for: model), id: \.self) { source in
                    choice(source.shortTitle, symbol: source.symbol, selected: source == model.source) { model.setSource(source) }
                }
            }
            Text(model.source.hint)
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .fixedSize(horizontal: false, vertical: true)
            if model.source != .system {
                HStack(spacing: 8) {
                    Text(tr("Microphone", "마이크"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.interim)
                    PillMenuButton(
                        title: String(SourceMenu.microphoneName(for: model).prefix(28)), palette: palette,
                        tip: tr("Which microphone to listen with", "어느 마이크로 들을지"),
                        accessibility: tr("Microphone", "마이크"),
                        makeMenu: { [model] in SourceMenu.menu(for: model) }
                    )
                }
            }
        }
    }

    private func choice(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.interim.opacity(selected ? 0.24 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.ink.opacity(selected ? 0.45 : 0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(_ scenario: Scenario) -> some View {
        let selected = scenario == model.scenario
        return Button(action: { model.setScenario(scenario) }) {
            HStack(spacing: 12) {
                Image(systemName: scenario.symbol)
                    .font(.system(size: 18))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.title).font(.system(size: 14, weight: .semibold))
                    Text(scenario.hint).font(.system(size: 12)).foregroundStyle(palette.interim)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.interim.opacity(selected ? 0.24 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.ink.opacity(selected ? 0.45 : 0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
