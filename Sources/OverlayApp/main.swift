import AppKit
import SwiftUI
import CaptionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let permissions = PermissionCenter()
    private var overlay: OverlayWindowController?
    private var menu: MenuBarController?
    private var hotKeys: HotKeyCenter?
    private var settingsWindow: AuxiliaryWindow?
    private var setupWindow: AuxiliaryWindow?
    private let whatsNewWindow = WhatsNewWindow()
    private let updater = Updater()
    private var updateWindow: UpdateWindow?
    private var observers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.choice = Preferences.uiLanguage

        setupWindow = AuxiliaryWindow(title: { tr("Permissions and setup", "권한 점검") }) { [weak self, model, permissions] in
            NSHostingView(rootView: SetupView(model: model, permissions: permissions) {
                Preferences.didShowSetup = true
                self?.setupWindow?.close()
            })
        }
        settingsWindow = AuxiliaryWindow(title: { tr("Ieum Settings", "Ieum 설정") }) { [weak self, model, updater] in
            NSHostingView(rootView: SettingsView(model: model, updater: updater, openSetup: { self?.setupWindow?.show() }, openWhatsNew: { self?.showWhatsNew() }))
        }

        updateWindow = UpdateWindow(updater: updater)
        updater.present = { [weak self] in self?.updateWindow?.show() }
        updater.isBusy = { [model] in model.isRunning }
        model.checkForUpdates = { [weak self] in self?.updater.checkNow() }
        model.openSettings = { [weak self] in self?.settingsWindow?.show() }
        model.openSetup = { [weak self] in self?.setupWindow?.show() }
        overlay = OverlayWindowController(model: model)
        model.bringOverlayToFront = { [weak self] in self?.overlay?.bringToFront() }
        model.overlayIsCovered = { [weak self] in self?.overlay?.isCoveredByAnotherWindow() ?? false }
        menu = MenuBarController(
            model: model,
            openSettings: { [weak self] in self?.settingsWindow?.show() },
            openSetup: { [weak self] in self?.setupWindow?.show() },
            checkForUpdates: { [weak self] in self?.updater.checkNow() }
        )
        overlay?.show()
        updater.start()

        hotKeys = HotKeyCenter(shortcuts: [
            .init(keyCode: 1) { [model] in model.toggleRunning() },          // S
            .init(keyCode: 4) { [model] in model.toggleOverlayVisible() },   // H
            .init(keyCode: 2) { [model] in model.cycleDisplayMode() },       // D
            .init(keyCode: 37) { [model] in model.swapDirection() },         // L
        ])
        hotKeys?.setEnabled(model.globalShortcuts)
        observers.append(model.$globalShortcuts.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            self?.hotKeys?.setEnabled(enabled)
        })

        if !Preferences.didShowSetup { setupWindow?.show() }
        showWhatsNewIfUpdated(firstInstall: !Preferences.didShowSetup)
        if Preferences.autoStart { model.start() }
    }

    /// After an update, a short tour of what changed. A first install gets the setup window instead.
    private func showWhatsNewIfUpdated(firstInstall: Bool) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let pages = WhatsNewCatalog.pending(lastSeen: Preferences.lastSeenVersion, current: version, isFirstInstall: firstInstall)
        Preferences.lastSeenVersion = version
        guard !pages.isEmpty else { return }
        // Let the overlay appear first, so the tour opens over a finished launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [whatsNewWindow] in whatsNewWindow.show(pages: pages, version: version) }
    }

    /// Opens the tour again with everything from the last few releases (Settings → About).
    func showWhatsNew() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        whatsNewWindow.show(pages: WhatsNewCatalog.pending(lastSeen: WhatsNew.baseline, current: version, isFirstInstall: false), version: version)
    }

    /// Let the recognizer deliver its last sentences and the transcript file close before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning else { return .terminateNow }
        // Race a clean stop against a 4 s limit with separate tasks: a task group would wait for the stop
        // even after the timeout fires (stop is not cancellable while a model download or prompt is pending).
        Task {
            await model.stop()
            finishTermination()
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            finishTermination()
        }
        return .terminateLater
    }

    private var terminationReplied = false

    private func finishTermination() {
        guard !terminationReplied else { return }
        terminationReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// Opening the app again (from Finder or Spotlight) while it runs shows the settings: there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
