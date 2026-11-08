import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var overlay: OverlayWindowController?
    private var menu: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayWindowController(model: model)
        menu = MenuBarController(model: model)
        overlay?.show()
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
