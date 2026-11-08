import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import MacSTTCore
import Speech

/// Live state of everything the app needs from the system, for the setup screen.
@MainActor
final class PermissionCenter: ObservableObject {
    enum State {
        case granted, denied, notAsked

        var isGranted: Bool { self == .granted }
    }

    @Published private(set) var microphone: State = .notAsked
    @Published private(set) var screenAudio: State = .notAsked
    @Published private(set) var speech: State = .notAsked
    /// Nil when every needed translation language is installed; otherwise what to do about it.
    @Published private(set) var translationProblem: String?

    /// The compatibility engine (macOS before 26) is the only one that needs the speech-recognition permission.
    var needsSpeechPermission: Bool {
        if #available(macOS 26.0, *) { return false }
        return true
    }

    func refresh() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphone = .granted
        case .denied: microphone = .denied
        default: microphone = .notAsked
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = .granted
        case .notDetermined: speech = .notAsked
        default: speech = .denied
        }
        // macOS only says "granted" or not; "not granted" covers both "never asked" and "refused".
        screenAudio = CGPreflightScreenCaptureAccess() ? .granted : (Preferences.didRequestScreenAccess ? .denied : .notAsked)
        Task { await refreshTranslation() }
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        refresh()
    }

    func requestSpeech() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }
        refresh()
    }

    func requestScreenAudio() {
        Preferences.didRequestScreenAccess = true
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    private func refreshTranslation() async {
        var problems: [String] = []
        for pair in MeetingMode.conversation.translationPairs {
            if case .failure(let reason) = await SystemTranslation.makeTranslator(from: pair.source, to: pair.target) {
                problems.append(reason.message)
            }
        }
        translationProblem = problems.first
    }

    // MARK: System Settings

    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case screenAudio = "Privacy_ScreenCapture"
        case speech = "Privacy_SpeechRecognition"
    }

    static func openSystemSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openSystemSettingsApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Screen-recording permission only takes effect in a freshly started process.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
