import AppKit
import Combine

/// The only control surface: a status item with a menu. Rebuilt each time it opens so it never goes stale.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Live captions")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = statusLine(for: status)
    }

    private var statusLine: String { statusLine(for: model.status) }

    private func statusLine(for status: SessionStatus) -> String {
        switch status {
        case .idle: "Captions off"
        case .starting: "Starting…"
        case .listening: "Listening · \(model.language.title)"
        case .error(let message): message
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(action(model.isRunning ? "Stop captions" : "Start captions", #selector(toggleRunning)))
        menu.addItem(.separator())

        menu.addItem(submenu("Language", Language.allCases.map { language in
            choice(language.title, checked: language == model.language, #selector(chooseLanguage(_:)), language.rawValue)
        }))
        menu.addItem(submenu("Source", Source.allCases.map { source in
            choice(source.title, checked: source == model.source, #selector(chooseSource(_:)), source.rawValue)
        }))
        menu.addItem(submenu("Display", DisplayMode.allCases.map { mode in
            choice(mode.title, checked: mode == model.displayMode, #selector(chooseMode(_:)), mode.rawValue)
        }))
        menu.addItem(translationMenu())
        menu.addItem(submenu("Style", [
            submenu("Subtitle lines", Preferences.lineChoices.map { count in
                choice(count == 1 ? "1 line" : "\(count) lines", checked: count == model.barLines, #selector(chooseLines(_:)), String(count))
            }),
            submenu("Text size", TextSize.allCases.map { size in
                choice(size.title, checked: size == model.textSize, #selector(chooseTextSize(_:)), size.rawValue)
            }),
            submenu("Background", BackgroundStyle.allCases.map { style in
                choice(style.title, checked: style == model.background, #selector(chooseBackground(_:)), style.rawValue)
            }),
            .separator(),
            opacityItem(),
        ]))
        menu.addItem(.separator())

        if let file = model.scriptFile {
            menu.addItem(action("Show current transcript", #selector(revealTranscript)).with(object: file))
        }
        menu.addItem(action("Copy transcript", #selector(copyTranscript)))
        menu.addItem(action("Open transcript folder", #selector(openFolder)))
        menu.addItem(action("Choose transcript folder…", #selector(chooseFolder)))
        menu.addItem(.separator())
        menu.addItem(action("Quit", #selector(quit), key: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func choice(_ title: String, checked: Bool, _ selector: Selector, _ id: String) -> NSMenuItem {
        let item = action(title, selector)
        item.state = checked ? .on : .off
        item.representedObject = id
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    private func translationMenu() -> NSMenuItem {
        var items: [NSMenuItem] = []
        if let notice = model.translationNotice {
            let warning = NSMenuItem(title: "⚠︎ " + String(notice.prefix(70)) + (notice.count > 70 ? "…" : ""), action: nil, keyEquivalent: "")
            warning.isEnabled = false
            warning.toolTip = notice
            items.append(warning)
            items.append(.separator())
        }
        items += TranslationTarget.allCases.map { target in
            choice(target.title, checked: target == model.translationTarget, #selector(chooseTranslation(_:)), target.rawValue)
        }
        items.append(.separator())
        items += TranslationLayout.allCases.map { layout in
            choice(layout.title, checked: layout == model.translationLayout, #selector(chooseTranslationLayout(_:)), layout.rawValue)
        }
        let title = model.translationTarget == .off ? "Translation" : "Translation → \(model.translationTarget.title)"
        return submenu(title, items)
    }

    private func opacityItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = OpacityRow(value: model.backgroundOpacity) { [weak self] value in
            self?.model.setBackgroundOpacity(value)
        }
        return item
    }

    // MARK: Actions

    @objc private func chooseTranslation(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let target = TranslationTarget(rawValue: id) { model.setTranslationTarget(target) }
    }

    @objc private func chooseTranslationLayout(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let layout = TranslationLayout(rawValue: id) { model.setTranslationLayout(layout) }
    }

    @objc private func chooseLines(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String, let count = Int(text) { model.setBarLines(count) }
    }

    @objc private func chooseTextSize(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let size = TextSize(rawValue: id) { model.setTextSize(size) }
    }

    @objc private func chooseBackground(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let style = BackgroundStyle(rawValue: id) { model.setBackground(style) }
    }

    @objc private func toggleRunning() {
        if model.isRunning { Task { await model.stop() } } else { model.start() }
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let language = Language(rawValue: id) { model.setLanguage(language) }
    }

    @objc private func chooseSource(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let source = Source(rawValue: id) { model.setSource(source) }
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let mode = DisplayMode(rawValue: id) { model.setDisplayMode(mode) }
    }

    @objc private func revealTranscript(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.transcriptText(), forType: .string)
    }

    @objc private func openFolder() {
        let directory = Preferences.scriptDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where transcripts are saved."
        panel.directoryURL = Preferences.scriptDirectory
        if panel.runModal() == .OK, let url = panel.url { model.setScriptDirectory(url) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    func with(object: Any) -> NSMenuItem {
        representedObject = object
        return self
    }
}

/// A labelled slider shown inside the menu. Dragging updates the overlay live while the menu stays open.
private final class OpacityRow: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let onChange: (Double) -> Void

    init(value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: Preferences.opacityRange.lowerBound, maxValue: Preferences.opacityRange.upperBound, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 50))
        label.font = .menuFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 28, width: 200, height: 17)
        slider.frame = NSRect(x: 20, y: 6, width: 200, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        addSubview(label)
        addSubview(slider)
        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func changed() {
        updateLabel()
        onChange(slider.doubleValue)
    }

    private func updateLabel() {
        label.stringValue = "Background opacity  \(Int((slider.doubleValue * 100).rounded()))%"
    }
}
