import SwiftUI

/// First-run welcome and permission check. It also opens from the menu whenever something is blocked.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionCenter
    let onDone: () -> Void
    /// The restart hint only matters once the person has gone to System Settings.
    @State private var screenAudioRequested = false

    var body: some View {
        // Reading `uiLanguage` makes the whole screen follow the language setting.
        let _ = model.uiLanguage
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Welcome to Ieum", "Ieum 시작하기"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(tr("Live captions and translation for meetings, entirely on this Mac. Your voice is never sent anywhere.",
                            "회의용 실시간 자막과 번역입니다. 모든 처리는 이 Mac 안에서 이루어지고 음성은 어디로도 전송되지 않습니다."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                PermissionRow(
                    title: tr("Microphone", "마이크"),
                    detail: tr("Hears the people in the room.", "회의실에 있는 사람들의 목소리를 듣습니다."),
                    state: permissions.microphone,
                    allow: { Task { await permissions.requestMicrophone() } },
                    open: { PermissionCenter.openSystemSettings(.microphone) }
                )
                Divider()
                PermissionRow(
                    title: tr("Screen & system audio recording", "화면 및 시스템 오디오 녹음"),
                    detail: tr("Only needed to caption what plays on this Mac, such as a video call or a video.",
                               "화상회의나 영상처럼 이 Mac에서 재생되는 소리를 자막으로 만들 때만 필요합니다."),
                    state: permissions.screenAudio,
                    allow: { screenAudioRequested = true; permissions.requestScreenAudio() },
                    open: { screenAudioRequested = true; PermissionCenter.openSystemSettings(.screenAudio) },
                    isOptional: true,
                    note: permissions.screenAudio.isGranted || !screenAudioRequested ? nil : tr(
                        "After you turn it on, quit and reopen the app. If it is on but still blocked, remove Ieum from the list and add it again.",
                        "켠 뒤에는 앱을 완전히 종료했다가 다시 여세요. 켜져 있는데도 막혀 있다면 목록에서 Ieum를 삭제하고 다시 추가하세요."
                    ),
                    noteAction: permissions.screenAudio.isGranted || !screenAudioRequested ? nil : (tr("Quit and reopen", "종료 후 다시 열기"), { PermissionCenter.relaunch() })
                )
                if permissions.needsSpeechPermission || model.showsWordsSooner {
                    Divider()
                    PermissionRow(
                        title: tr("Speech recognition", "음성 인식"),
                        detail: permissions.needsSpeechPermission
                            ? tr("Needed by the speech engine on this macOS version.", "이 macOS 버전의 음성 엔진에 필요합니다.")
                            : tr("Shows the first words about half a second sooner. Without it captions still work, just a little later.",
                                 "첫 단어를 약 0.5초 일찍 보여 줍니다. 허용하지 않아도 자막은 나오며 조금 늦을 뿐입니다."),
                        state: permissions.speech,
                        allow: { Task { await permissions.requestSpeech() } },
                        open: { PermissionCenter.openSystemSettings(.speech) },
                        isOptional: !permissions.needsSpeechPermission
                    )
                }
                Divider()
                PermissionRow(
                    title: Preferences.meetingSetup.translates ? tr("\(Preferences.meetingSetup.title) translation", "\(Preferences.meetingSetup.title) 번역") : tr("Translation", "번역"),
                    detail: permissions.translationProblem
                        ?? tr("Offline translation is ready.", "오프라인 번역을 쓸 수 있습니다."),
                    state: permissions.translationProblem == nil ? .granted : .denied,
                    allow: {},
                    open: { PermissionCenter.openSystemSettingsApp() },
                    openLabel: tr("Open System Settings", "시스템 설정 열기")
                )
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))

            SelfTestCard(model: model, microphoneReady: permissions.microphone.isGranted)

            HStack {
                Text(tr("You can open this screen again from the menu bar icon.", "메뉴 막대 아이콘에서 이 화면을 다시 열 수 있습니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("Done", "완료"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { permissions.refresh() }
        .task {
            // The user flips switches in System Settings; keep the status current while this window is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                permissions.refresh()
            }
        }
    }
}

/// The first-run test: a sentence is played through the speakers and must come back as captions and a translation.
private struct SelfTestCard: View {
    @ObservedObject var model: AppModel
    let microphoneReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Try it", "체험해 보기")).font(.system(size: 14, weight: .medium))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if model.selfTest == .running {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.selfTest == .idle ? tr("Run test", "테스트 실행") : tr("Run again", "다시 실행")) { model.runSelfTest() }
                        .disabled(!microphoneReady || model.isRunning)
                }
            }
            if case .passed(let heard, let translation) = model.selfTest {
                VStack(alignment: .leading, spacing: 3) {
                    Text(heard).font(.system(size: 12)).foregroundStyle(.secondary)
                    if let translation { Text(translation).font(.system(size: 14, weight: .medium)) }
                }
                .textSelection(.enabled)
                .padding(.leading, 32)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder
    private var icon: some View {
        switch model.selfTest {
        case .passed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.green)
                .accessibilityLabel(tr("Passed", "통과"))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.orange)
                .accessibilityLabel(tr("Needs attention", "확인 필요"))
        default:
            Image(systemName: "play.circle").font(.system(size: 20)).foregroundStyle(Color.secondary)
        }
    }

    private var detail: String {
        switch model.selfTest {
        case .idle:
            return microphoneReady
                ? tr("Plays a short English sentence through the speakers and shows it as captions with a Korean translation. About 15 seconds, and it is audible.",
                     "짧은 영어 문장을 스피커로 들려주고 자막과 한국어 번역으로 보여 줍니다. 약 15초 걸리고 소리가 납니다.")
                : tr("Allow the microphone first.", "먼저 마이크를 허용하세요.")
        case .running:
            return tr("Listening to the test sentence…", "테스트 문장을 듣는 중…")
        case .passed(_, let translation):
            return translation == nil
                ? tr("Heard and recognized. The translation did not arrive yet: check the translation row above.", "들리고 인식됐습니다. 번역은 아직 오지 않았습니다. 위의 번역 항목을 확인하세요.")
                : tr("It works: this Mac heard, recognized and translated the sentence. You are ready for a meeting.", "정상 작동합니다. 이 Mac이 문장을 듣고 인식하고 번역했습니다. 회의에 쓸 준비가 됐습니다.")
        case .failed(let message):
            return message
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionCenter.State
    let allow: () -> Void
    let open: () -> Void
    var openLabel: String?
    var isOptional = false
    var note: String?
    var noteAction: (String, () -> Void)?

    private var icon: String {
        if state.isGranted { return "checkmark.circle.fill" }
        return isOptional ? "circle.dashed" : "exclamationmark.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(state.isGranted ? Color.green : (isOptional ? Color.secondary : (state == .denied ? Color.orange : Color.secondary)))
                    .accessibilityLabel(state.isGranted ? tr("Allowed", "허용됨") : (isOptional ? tr("Optional, not allowed", "선택 사항, 허용 안 됨") : tr("Needs attention", "확인 필요")))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 14, weight: .medium))
                        if isOptional && !state.isGranted {
                            Text(tr("Optional", "선택"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if !state.isGranted {
                    if state == .notAsked, openLabel == nil {
                        Button(tr("Allow", "허용"), action: allow)
                    } else {
                        Button(openLabel ?? tr("Open Settings", "설정 열기"), action: open)
                    }
                }
            }
            if let note {
                HStack(alignment: .firstTextBaseline) {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let noteAction {
                        Spacer(minLength: 8)
                        Button(noteAction.0, action: noteAction.1).controlSize(.small)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(14)
    }
}
