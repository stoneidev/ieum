import AppKit
import Combine
import CaptionCore

/// The menu-bar icon and its short menu: what you need while a meeting is running. Everything else lives in Settings.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item: NSStatusItem
    private let openSettings: () -> Void
    private let openSetup: () -> Void
    private let checkForUpdates: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, openSettings: @escaping () -> Void, openSetup: @escaping () -> Void, checkForUpdates: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        self.openSetup = openSetup
        self.checkForUpdates = checkForUpdates
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A name of its own: unnamed items are saved as "Item-0", "Item-1"… and share their visibility (and a hidden
        // state set for another app's item) with every other app's unnamed item.
        item.autosaveName = "today.calmwork.ieum.status"
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon(for: model.status)
        // `@Published` emits before the property changes, so use the emitted value, never `model.status`.
        model.$status
            .sink { [weak self] status in self?.updateIcon(for: status) }
            .store(in: &cancellables)
    }

    private func updateIcon(for status: SessionStatus) {
        let symbol = status.isRunning ? "captions.bubble.fill" : "captions.bubble"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tr("Live captions", "실시간 자막"))
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = statusLine(for: status)
    }

    private func statusLine(for status: SessionStatus) -> String {
        switch status {
        case .idle: tr("Captions off", "자막 꺼짐")
        case .starting: tr("Starting…", "시작하는 중…")
        case .listening: model.transcriptWarning.map { "⚠︎ " + $0 } ?? tr("Listening · \(model.setup.title)", "듣는 중 · \(model.setup.title)")
        case .error(let message): message
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine(for: model.status), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if case .error = model.status {
            menu.addItem(action(tr("Fix this…", "해결하기…"), #selector(showSetup)))
        }
        menu.addItem(.separator())

        let toggle = action(model.isRunning ? tr("Stop captions", "자막 중지") : tr("Start captions", "자막 시작"), #selector(toggleRunning), key: "s")
        toggle.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggle)

        let heard = NSMenu()
        heard.autoenablesItems = false
        for language in SpokenLanguage.allCases {
            let entry = action(language.nativeName, #selector(chooseHeard(_:)))
            entry.representedObject = language.rawValue
            entry.state = language == model.setup.heard ? .on : .off
            heard.addItem(entry)
        }
        let heardItem = NSMenuItem(title: tr("Language you hear", "듣는 언어"), action: nil, keyEquivalent: "")
        heardItem.submenu = heard
        menu.addItem(heardItem)

        let shown = NSMenu()
        shown.autoenablesItems = false
        for language in SpokenLanguage.allCases {
            let entry = action(language.nativeName, #selector(chooseShown(_:)))
            entry.representedObject = language.rawValue
            entry.state = language == model.setup.shown ? .on : .off
            shown.addItem(entry)
        }
        shown.addItem(.separator())
        let none = action(tr("No translation (captions only)", "번역 없음 (자막만)"), #selector(chooseShown(_:)))
        none.state = model.setup.shown == nil ? .on : .off
        shown.addItem(none)
        let shownItem = NSMenuItem(title: tr("Language you read", "보는 언어"), action: nil, keyEquivalent: "")
        shownItem.submenu = shown
        menu.addItem(shownItem)

        let both = action(tr("Both sides speak (detect the language)", "서로 번갈아 말함 (언어 자동 인식)"), #selector(toggleBothWays))
        both.state = model.setup.bothWays ? .on : .off
        both.isEnabled = model.setup.translates && MeetingSetup.bothWaysIsAvailableOnThisMac
        both.toolTip = MeetingSetup.bothWaysIsAvailableOnThisMac ? model.setup.explanation : tr("Needs macOS 26 or later.", "macOS 26 이상이 필요합니다.")
        menu.addItem(both)
        let swap = action(tr("Swap languages", "언어 바꾸기"), #selector(swapDirection), key: "l")
        swap.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(swap)
        menu.addItem(.separator())

        let visibility = action(model.overlayVisible ? tr("Hide overlay", "오버레이 숨기기") : tr("Show overlay", "오버레이 보이기"), #selector(toggleOverlay), key: "h")
        visibility.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(visibility)
        let onTop = action(tr("Keep on top of other windows", "다른 창 위에 항상 표시"), #selector(toggleKeepOnTop))
        onTop.state = model.keepsOnTop ? .on : .off
        menu.addItem(onTop)
        if !model.keepsOnTop {
            menu.addItem(action(tr("Bring captions to the front", "자막을 앞으로 가져오기"), #selector(bringToFront)))
        }
        let display = action(model.displayMode == .bar ? tr("Switch to transcript panel", "기록 패널로 전환") : tr("Switch to subtitle bar", "자막 바로 전환"), #selector(cycleDisplay), key: "d")
        display.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(display)
        menu.addItem(.separator())

        menu.addItem(action(tr("Copy transcript", "기록 복사"), #selector(copyTranscript)))
        let nameMeeting = action(tr("Name this meeting…", "이 회의에 이름 붙이기…"), #selector(nameMeeting))
        nameMeeting.isEnabled = model.canNameLastTranscript
        menu.addItem(nameMeeting)
        menu.addItem(action(tr("Open transcript folder", "기록 폴더 열기"), #selector(openFolder)))
        menu.addItem(.separator())

        menu.addItem(action(tr("Check for updates…", "업데이트 확인…"), #selector(updateCheck)))
        menu.addItem(action(tr("Permissions and setup…", "권한 및 설정 점검…"), #selector(showSetup)))
        menu.addItem(action(tr("Settings…", "설정…"), #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action(tr("Quit Ieum", "Ieum 종료"), #selector(quit), key: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: Actions

    @objc private func toggleRunning() { model.toggleRunning() }
    @objc private func toggleOverlay() { model.toggleOverlayVisible() }
    @objc private func bringToFront() { model.bringOverlayToFront() }
    @objc private func toggleKeepOnTop() { model.setKeepsOnTop(!model.keepsOnTop) }
    @objc private func swapDirection() { model.swapDirection() }
    @objc private func cycleDisplay() { model.cycleDisplayMode() }
    @objc private func showSettings() { openSettings() }
    @objc private func updateCheck() { checkForUpdates() }
    @objc private func showSetup() { openSetup() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseHeard(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let language = SpokenLanguage(rawValue: id) { model.setHeard(language) }
    }

    /// The "captions only" entry carries no language, which stands for no translation.
    @objc private func chooseShown(_ sender: NSMenuItem) {
        model.setShown((sender.representedObject as? String).flatMap(SpokenLanguage.init(rawValue:)))
    }

    @objc private func toggleBothWays() { model.setBothWays(!model.setup.bothWays) }

    @objc private func nameMeeting() { model.renameLastTranscript() }

    @objc private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.transcriptText(), forType: .string)
    }

    @objc private func openFolder() {
        let directory = Preferences.scriptDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
