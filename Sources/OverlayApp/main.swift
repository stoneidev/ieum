import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let permissions = PermissionCenter()
    private var overlay: OverlayWindowController?
    private var menu: MenuBarController?
    private var hotKeys: HotKeyCenter?
    private var settingsWindow: AuxiliaryWindow?
    private var setupWindow: AuxiliaryWindow?
    private var observers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.choice = Preferences.uiLanguage

        setupWindow = AuxiliaryWindow(title: { tr("Permissions and setup", "권한 점검") }) { [weak self, model, permissions] in
            NSHostingView(rootView: SetupView(model: model, permissions: permissions) {
                Preferences.didShowSetup = true
                self?.setupWindow?.close()
            })
        }
        settingsWindow = AuxiliaryWindow(title: { tr("Ieum Settings", "Ieum 설정") }) { [weak self, model] in
            NSHostingView(rootView: SettingsView(model: model) { self?.setupWindow?.show() })
        }

        overlay = OverlayWindowController(model: model)
        menu = MenuBarController(
            model: model,
            openSettings: { [weak self] in self?.settingsWindow?.show() },
            openSetup: { [weak self] in self?.setupWindow?.show() }
        )
        overlay?.show()

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
        if Preferences.autoStart { model.start() }
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
