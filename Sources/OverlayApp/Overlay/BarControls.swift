import AppKit
import CaptionCore
import SwiftUI

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

            let situations = NSMenu()
            situations.autoenablesItems = false
            for scenario in Scenario.allCases {
                situations.addItem(ActionItem(scenario.title, checked: scenario == model.scenario) { model.setScenario(scenario) })
            }
            let situationItem = NSMenuItem(title: tr("Situation: ", "상황: ") + model.scenario.title, action: nil, keyEquivalent: "")
            situationItem.submenu = situations
            menu.addItem(situationItem)

            let heard = NSMenu()
            heard.autoenablesItems = false
            for language in SpokenLanguage.allCases {
                heard.addItem(ActionItem(language.nativeName, checked: language == model.setup.heard) { model.setHeard(language) })
            }
            let heardItem = NSMenuItem(title: tr("Language you hear", "듣는 언어"), action: nil, keyEquivalent: "")
            heardItem.submenu = heard
            menu.addItem(heardItem)

            let shown = NSMenu()
            shown.autoenablesItems = false
            for language in SpokenLanguage.allCases {
                shown.addItem(ActionItem(language.nativeName, checked: language == model.setup.shown) { model.setShown(language) })
            }
            shown.addItem(.separator())
            shown.addItem(ActionItem(tr("No translation (captions only)", "번역 없음 (자막만)"), checked: model.setup.shown == nil) { model.setShown(nil) })
            let shownItem = NSMenuItem(title: tr("Language you read", "보는 언어"), action: nil, keyEquivalent: "")
            shownItem.submenu = shown
            menu.addItem(shownItem)

            if model.scenario.allowsBothWays {
                menu.addItem(ActionItem(tr("Both sides speak (detect the language)", "서로 번갈아 말함 (언어 자동 인식)"), checked: model.setup.bothWays,
                                        enabled: model.setup.translates && MeetingSetup.bothWaysIsAvailableOnThisMac) { model.setBothWays(!model.setup.bothWays) })
            }
            menu.addItem(ActionItem(tr("Swap languages", "언어 바꾸기")) { model.swapDirection() })
            menu.addItem(SourceMenu.submenuItem(for: model))

            let sizes = NSMenu()
            sizes.autoenablesItems = false
            for size in TextSize.allCases {
                sizes.addItem(ActionItem(size.title, checked: size == model.textSize) { model.setTextSize(size) })
            }
            let sizeItem = NSMenuItem(title: tr("Text size", "글자 크기"), action: nil, keyEquivalent: "")
            sizeItem.submenu = sizes
            menu.addItem(sizeItem)

            menu.addItem(ActionItem(model.displayMode == .bar ? tr("Show transcript panel", "기록 패널로 전환") : tr("Show subtitle bar", "자막 바로 전환")) { model.cycleDisplayMode() })
            menu.addItem(ActionItem(tr("Keep on top of other windows", "다른 창 위에 항상 표시"), checked: model.keepsOnTop) { model.setKeepsOnTop(!model.keepsOnTop) })
            menu.addItem(ActionItem(tr("Hide from screen sharing", "화면 공유에서 숨기기"), checked: model.hidesFromSharing) { model.setHidesFromSharing(!model.hidesFromSharing) })
            if !model.keepsOnTop {
                menu.addItem(ActionItem(tr("Bring captions to the front", "자막을 앞으로 가져오기")) { model.bringOverlayToFront() })
            }
            menu.addItem(.separator())
            menu.addItem(ActionItem(
                (model.isPaused ? tr("Resume captions", "자막 다시 시작") : tr("Pause captions", "자막 일시정지"))
                    + (model.globalShortcuts ? "   ⌃⌥P" : ""),
                enabled: model.canPause || model.isPaused
            ) { model.togglePause() })
            menu.addItem(ActionItem(tr("New conversation", "새 대화"), enabled: model.canStartNewConversation) { model.startNewConversation() })
            menu.addItem(ActionItem(tr("Name this meeting…", "이 회의에 이름 붙이기…"), enabled: model.canNameLastTranscript) { model.renameLastTranscript() })
            if model.offersMinutes {
                menu.addItem(ActionItem(model.scenario.notesTitle + tr(" draft…", " 초안…"), enabled: model.canMakeMinutes) { model.showMinutes(start: true) })
            }
            menu.addItem(ActionItem(tr("Reply helper…", "답장 도우미…") + (model.globalShortcuts ? "   ⌃⌥R" : "")) { model.openReply() })
            menu.addItem(ActionItem(tr("Settings…", "설정…")) { model.openSettings() })
            menu.addItem(ActionItem("☕ " + tr("Buy me a coffee…", "커피 한 잔 사주기…")) { model.openCoffeePageFromMenu() })
            menu.addItem(ActionItem(tr("Check for updates…", "업데이트 확인…")) { model.checkForUpdates() })
            menu.addItem(ActionItem(tr("Permissions and setup…", "권한 및 설정 점검…")) { model.openSetup() })
            menu.addItem(.separator())
            menu.addItem(ActionItem(tr("Quit Ieum", "Ieum 종료")) { NSApp.terminate(nil) })
            return menu
        }
    }
}

/// Text size, bar/panel and the menu, together in the corner of the subtitle bar. On the live bar they stay quiet
/// until the pointer comes near, so nothing competes with the words, but the menu is always one click away.
struct BarControls: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    let subdued: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            sizeButton(delta: -1, label: "A", pointSize: 12, help: tr("Smaller text", "글자 작게"))
            sizeButton(delta: 1, label: "A", pointSize: 17, help: tr("Larger text", "글자 크게"))
            ReplyButton(model: model, palette: palette)
            DisplayToggleButton(model: model, palette: palette)
            OverlayMenuButton(model: model, palette: palette)
            QuitButton(model: model, palette: palette)
        }
        .opacity(subdued && !hovering ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func sizeButton(delta: Int, label: String, pointSize: CGFloat, help: String) -> some View {
        let all = TextSize.allCases
        let target = all.firstIndex(of: model.textSize).map { $0 + delta }
        let enabled = target.map(all.indices.contains) ?? false
        return Button(action: { model.stepTextSize(by: delta) }) {
            Text(label)
                .font(.system(size: pointSize, weight: .semibold))
                .foregroundStyle(palette.interim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.ink.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One click between the subtitle bar and the transcript panel (⌃⌥D does the same). It sits on both, in the same corner.
struct DisplayToggleButton: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    @State private var hovering = false

    var body: some View {
        let toPanel = model.displayMode == .bar
        let label = toPanel ? tr("Show the transcript panel", "기록 패널로 전환") : tr("Show the subtitle bar", "자막 바로 전환")
        Button(action: { model.cycleDisplayMode() }) {
            Image(systemName: toPanel ? "list.bullet.rectangle" : "rectangle.bottomthird.inset.filled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.interim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.ink.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label + (model.globalShortcuts ? "  ⌃⌥D" : ""))
        .accessibilityLabel(label)
    }
}

/// Closes the whole program from the overlay, next to the menu: the menu-bar icon can be hidden when the menu bar is full.
struct QuitButton: View {
    let model: AppModel
    let palette: Theme.Palette
    @State private var hovering = false

    var body: some View {
        let label = tr("Quit Ieum", "Ieum 종료")
        Button(action: { model.requestQuit() }) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Theme.alert : palette.interim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.ink.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Opens the reply helper: say what you mean in your language, get a sentence to read out in theirs.
struct ReplyButton: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    @State private var hovering = false

    var body: some View {
        let label = tr("Reply helper: write it in your language, read it out in theirs", "답장 도우미: 내 언어로 쓰면 상대 언어 문장을 알려 줍니다")
        Button(action: { model.openReply() }) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.interim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.ink.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label + (model.globalShortcuts ? "  ⌃⌥R" : ""))
        .accessibilityLabel(tr("Reply helper", "답장 도우미"))
    }
}
