import SwiftUI
import CaptionCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    let openSetup: () -> Void
    let openWhatsNew: () -> Void
    /// The last tab you used is the one you see next time.
    @AppStorage("settingsTab") private var tab = 0

    var body: some View {
        let _ = model.uiLanguage // follow the language setting
        TabView(selection: $tab) {
            GeneralTab(model: model, updater: updater).tag(0)
                .tabItem { Label(tr("General", "일반"), systemImage: "gearshape") }
            DisplayTab(model: model).tag(1)
                .tabItem { Label(tr("Display", "화면"), systemImage: "captions.bubble") }
            VocabularyTab(model: model).tag(2)
                .tabItem { Label(tr("Vocabulary", "용어집"), systemImage: "text.book.closed") }
            TranscriptsTab(model: model).tag(3)
                .tabItem { Label(tr("Transcripts", "기록"), systemImage: "doc.text") }
            AboutTab(updater: updater, openSetup: openSetup, openWhatsNew: openWhatsNew).tag(4)
                .tabItem { Label(tr("About", "정보"), systemImage: "info.circle") }
        }
        .frame(width: 600, height: 760)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @State private var autoCheck = Preferences.autoCheckUpdates
    @State private var loginEnabled = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var inputDevices = InputDevices.available()

    private var lastCheckText: String {
        guard let date = updater.lastCheck else { return tr("Not checked yet", "아직 확인하지 않았습니다") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.isKorean ? "ko" : "en")
        return tr("Last checked ", "마지막 확인: ") + formatter.localizedString(for: date, relativeTo: Date())
    }

    private var shortcuts: [(key: String, title: String)] { [
        ("S", tr("Start / stop", "시작/중지")),
        ("H", tr("Show / hide", "보이기/숨기기")),
        ("D", tr("Bar / panel", "바/패널")),
        ("L", tr("Swap language direction", "언어 방향 바꾸기")),
    ] }

    var body: some View {
        Form {
            Section(tr("Meeting", "회의")) {
                HStack(spacing: 10) {
                    Picker(tr("Language you hear", "듣는 언어"), selection: Binding(get: { model.setup.heard }, set: model.setHeard)) {
                        ForEach(SpokenLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
                    }
                    Button(action: model.swapDirection) { Image(systemName: "arrow.left.arrow.right") }
                        .buttonStyle(.borderless)
                        .help(tr("Swap languages", "언어 바꾸기") + (model.globalShortcuts ? "  ⌃⌥L" : ""))
                        .accessibilityLabel(tr("Swap languages", "언어 바꾸기"))
                    Picker(tr("Language you read", "보는 언어"), selection: Binding(get: { model.setup.shown }, set: model.setShown)) {
                        ForEach(SpokenLanguage.allCases, id: \.self) { Text($0.nativeName).tag(SpokenLanguage?.some($0)) }
                        Divider()
                        Text(tr("No translation (captions only)", "번역 없음 (자막만)")).tag(SpokenLanguage?.none)
                    }
                }
                Toggle(tr("Both sides speak (detect the language)", "서로 번갈아 말함 (언어 자동 인식)"), isOn: Binding(get: { model.setup.bothWays }, set: model.setBothWays))
                    .disabled(!model.setup.translates || !MeetingSetup.bothWaysIsAvailableOnThisMac || model.source == .call)
                Text(MeetingSetup.bothWaysIsAvailableOnThisMac || !model.setup.translates
                     ? model.setup.explanation
                     : model.setup.explanation + " " + tr("Detecting the language needs macOS 26 or later.", "언어 자동 인식은 macOS 26 이상이 필요합니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = model.transcriptWarning {
                    Text(warning).font(.system(size: 12)).foregroundStyle(.orange)
                }

                if model.setup.recognizesEnglish {
                    Picker(tr("English accent", "영어 억양"), selection: Binding(get: { model.englishVariant }, set: model.setEnglishVariant)) {
                        Text(Language.englishUS.title).tag(Language.englishUS)
                        Text(Language.englishAU.title).tag(Language.englishAU)
                    }
                }
                Picker(tr("Audio source", "소리 입력"), selection: Binding(get: { model.source }, set: model.setSource)) {
                    ForEach(Source.allCases.filter(\.isAvailableOnThisMac), id: \.self) { Text($0.title).tag($0) }
                }
                if model.source == .microphone || model.source == .call {
                    Picker(tr("Microphone", "마이크"), selection: Binding(get: { model.inputDeviceUID }, set: model.setInputDevice)) {
                        Text(tr("System default", "시스템 기본값")).tag(String?.none)
                        ForEach(inputDevices) { Text($0.name).tag(String?.some($0.uid)) }
                        // A saved microphone that is not plugged in stays selectable so the choice is not lost silently.
                        if let saved = model.inputDeviceUID, !inputDevices.contains(where: { $0.uid == saved }) {
                            Text(tr("Not connected (using the default)", "연결 안 됨 (기본값 사용)")).tag(String?.some(saved))
                        }
                    }
                }
                if model.source == .call {
                    let theirs = model.setup.heard.name, mine = (model.setup.shown ?? model.setup.heard).name
                    Text(tr("For video calls: the other side (system audio) is read as \(theirs), you (microphone) as \(mine). Each line says who spoke, and both directions are translated. Headphones work best; with speakers Ieum filters out the echo. Needs the Screen & System Audio Recording permission.",
                            "화상 통화용: 상대(시스템 소리)는 \(theirs), 나(마이크)는 \(mine)로 인식합니다. 줄마다 누가 말했는지 표시되고 두 방향을 모두 번역합니다. 헤드폰이 가장 좋고, 스피커를 쓰면 에코를 걸러 냅니다. 화면 및 시스템 오디오 녹음 권한이 필요합니다."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if model.source == .system {
                    Text(tr("Captions what plays on this Mac (calls, videos). Needs the Screen & System Audio Recording permission.",
                            "이 Mac에서 재생되는 소리(화상회의, 영상)를 자막으로 만듭니다. 화면 및 시스템 오디오 녹음 권한이 필요합니다."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section(tr("App", "앱")) {
                Toggle(tr("Open at login", "로그인할 때 열기"), isOn: Binding(get: { loginEnabled }, set: { value in
                    loginError = LaunchAtLogin.set(value)
                    loginEnabled = LaunchAtLogin.isEnabled
                }))
                if let loginError {
                    Text(loginError).font(.system(size: 12)).foregroundStyle(.orange)
                }
                Toggle(tr("Show words sooner", "단어를 더 빨리 보이기"), isOn: Binding(get: { model.showsWordsSooner }, set: model.setShowsWordsSooner))
                Text(tr("Runs a second recognizer so the first words appear about half a second earlier and then word by word. Finished sentences are still recognized by the more accurate one. Needs the Speech Recognition permission. Applies the next time captions start, and not when the language is detected automatically.",
                        "두 번째 인식기를 함께 돌려 첫 단어가 약 0.5초 일찍, 이후 단어마다 바로 나옵니다. 끝난 문장은 계속 더 정확한 인식기가 확정합니다. 음성 인식 권한이 필요합니다. 다음에 자막을 시작할 때부터 적용되며 언어 자동 인식 번역 모드에서는 쓰이지 않습니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Toggle(tr("Global shortcuts", "전역 단축키"), isOn: Binding(get: { model.globalShortcuts }, set: model.setGlobalShortcuts))
                if model.globalShortcuts {
                    ForEach(shortcuts, id: \.key) { shortcut in
                        LabeledContent(shortcut.title) {
                            HStack(spacing: 4) {
                                ForEach(["⌃", "⌥", shortcut.key], id: \.self) { Keycap(label: $0) }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Control Option \(shortcut.key)")
                        }
                    }
                }
                Toggle(tr("Check for updates automatically", "업데이트를 자동으로 확인"), isOn: Binding(get: { autoCheck }, set: { value in
                    autoCheck = value
                    Preferences.autoCheckUpdates = value
                }))
                Text(tr("Once a day Ieum asks ieum.calmwork.today which version is newest, and asks you before installing anything. That request carries no audio, no text and no identifiers. Turn it off and Ieum makes no network requests at all.",
                        "하루에 한 번 ieum.calmwork.today에 최신 버전을 묻고, 설치하기 전에 먼저 물어봅니다. 이 요청에는 음성도, 글자도, 식별 정보도 없습니다. 끄면 Ieum은 네트워크 요청을 전혀 하지 않습니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(tr("Check now", "지금 확인")) { updater.checkNow() }
                    Text(lastCheckText).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Picker(tr("Interface language", "화면 언어"), selection: Binding(get: { model.uiLanguage }, set: model.setUILanguage)) {
                    Text(tr("Follow the system", "시스템 설정 따르기")).tag("system")
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { inputDevices = InputDevices.available() }
    }
}

/// One key of a shortcut, drawn like the key on a keyboard.
private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Display

private struct DisplayTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            CaptionPreview(model: model)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 2)
            form
        }
    }

    private var form: some View {
        Form {
            Section(tr("Captions", "자막")) {
                Picker(tr("Show as", "표시 방식"), selection: Binding(get: { model.displayMode }, set: model.setDisplayMode)) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(tr("Lines in the subtitle bar", "자막 바 줄 수"), selection: Binding(get: { model.barLines }, set: model.setBarLines)) {
                    ForEach(Preferences.lineChoices, id: \.self) { Text(tr("\($0)", "\($0)줄")).tag($0) }
                }
                Picker(tr("Text size", "글자 크기"), selection: Binding(get: { model.textSize }, set: model.setTextSize)) {
                    ForEach(TextSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if model.setup.translates {
                    Picker(tr("Translation", "번역 표시"), selection: Binding(get: { model.translationLayout }, set: model.setTranslationLayout)) {
                        ForEach(TranslationLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            Section(tr("Background", "배경")) {
                Picker(tr("Style", "스타일"), selection: Binding(get: { model.background }, set: model.setBackground)) {
                    ForEach(BackgroundStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    Text(tr("Opacity", "투명도"))
                    Slider(value: Binding(get: { model.backgroundOpacity }, set: model.setBackgroundOpacity), in: Preferences.opacityRange)
                    Text("\(Int((model.backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text(tr("Only the background becomes see-through. The text always stays fully visible.",
                        "배경만 투명해지고 글자는 항상 또렷하게 보입니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Section(tr("Stay out of the way", "회의를 가리지 않게")) {
                Toggle(tr("Keep captions on top of other windows", "자막을 다른 창 위에 항상 표시"), isOn: Binding(get: { model.keepsOnTop }, set: model.setKeepsOnTop))
                if !model.keepsOnTop {
                    Text(tr("Other windows can cover the captions, like any window. Press ⌃⌥H to bring them back to the front.",
                            "다른 창이 자막을 가릴 수 있습니다(일반 창처럼). ⌃⌥H를 누르면 자막이 앞으로 나옵니다."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Toggle(tr("Click through the overlay", "오버레이 클릭 통과"), isOn: Binding(get: { model.clickThrough }, set: model.setClickThrough))
                if model.clickThrough {
                    Text(tr("Clicks go to the window underneath. Turn this off to move or resize the overlay.",
                            "클릭이 아래 창으로 전달됩니다. 오버레이를 옮기거나 크기를 바꾸려면 끄세요."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var pendingApply: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Names and terms for this meeting", "이번 회의의 이름과 용어"))
                .font(.system(size: 15, weight: .semibold))
            Text(tr("One per line: people, products, company words. Wrongly heard words are corrected to your spelling, before translation, as soon as you type them.",
                    "한 줄에 하나씩 적으세요: 사람 이름, 제품명, 회사 용어. 잘못 들린 단어는 번역 전에 여기 적은 철자로 바로잡힙니다."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 14))
                .padding(6)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Example, replaced as soon as you type:", "예시, 입력하면 사라집니다:"))
                                .font(.system(size: 12, weight: .medium))
                            Text("Kubernetes\nSiobhan\nTerraform\n쿠버네티스")
                                .font(.system(size: 14, design: .monospaced))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Text(tr("\(model.vocabulary.count) terms", "용어 \(model.vocabulary.count)개"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .onAppear { text = model.vocabulary.joined(separator: "\n") }
        // A half-typed word must not go live in the middle of a meeting: apply after typing pauses, and on leaving.
        .onChange(of: text) { _, _ in
            pendingApply?.cancel()
            pendingApply = Task {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { apply() }
            }
        }
        .onDisappear {
            pendingApply?.cancel()
            apply()
        }
    }
}

extension VocabularyTab {
    fileprivate func apply() {
        model.setVocabulary(text.split(whereSeparator: \.isNewline).map(String.init))
    }
}

// MARK: - Transcripts

private struct TranscriptFile: Identifiable {
    let url: URL
    let modified: Date
    let bytes: Int
    var id: URL { url }
}

/// The minutes draft being written for one transcript.
private struct MinutesJob {
    let file: URL
    var done = 0
    var total = 1
    var task: Task<Void, Never>?
}

private struct MinutesError: LocalizedError {
    let errorDescription: String?
}

private struct TranscriptsTab: View {
    @ObservedObject var model: AppModel
    @State private var files: [TranscriptFile] = []
    @State private var pendingDelete: TranscriptFile?
    @State private var renaming: TranscriptFile?
    @State private var newName = ""
    @State private var renameError: String?
    @State private var minutesJob: MinutesJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Saved transcripts", "저장된 기록")).font(.system(size: 15, weight: .semibold))
                    Text(Preferences.scriptDirectory.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(tr("Choose Folder…", "폴더 선택…")) { chooseFolder() }
                Button(tr("Open Folder", "폴더 열기")) {
                    try? FileManager.default.createDirectory(at: Preferences.scriptDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Preferences.scriptDirectory)
                }
            }
            if files.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(tr("No transcripts yet", "아직 기록이 없습니다"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(tr("Each time you start captions, a new file is saved here, with the time of every sentence.",
                            "자막을 시작할 때마다 새 파일이 여기에 저장되고, 문장마다 시각이 함께 남습니다."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    if !model.isRunning {
                        Button(tr("Start captions", "자막 시작")) { model.start() }
                            .controlSize(.large)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(files) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.url.lastPathComponent).font(.system(size: 13))
                            Text("\(file.modified.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(tr("Open", "열기")) { NSWorkspace.shared.open(file.url) }.controlSize(.small)
                        Button(tr("Rename…", "이름 바꾸기…")) {
                            newName = file.url.deletingPathExtension().lastPathComponent
                            renaming = file
                        }
                        .controlSize(.small)
                        .disabled((model.isRunning && file.url == model.scriptFile) || minutesJob?.file == file.url || (model.isWritingMinutes && file.url == model.scriptFile))
                        .help(model.isRunning && file.url == model.scriptFile ? tr("Stop captions first.", "먼저 자막을 중지하세요.") : "")
                        Button(tr("Show in Finder", "Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.controlSize(.small)
                        if let job = minutesJob, job.file == file.url {
                            ProgressView(value: Double(job.done), total: Double(max(job.total, 1)))
                                .frame(width: 70)
                                .controlSize(.small)
                            Button(tr("Stop", "중지")) { job.task?.cancel() }.controlSize(.small)
                        } else {
                            Menu(tr("Export", "내보내기")) {
                                Button(tr("Subtitles (.srt)", "자막 파일 (.srt)")) { export(file, .srt, .both) }
                                Button(tr("Subtitles (.srt), translation only", "자막 파일 (.srt), 번역만")) { export(file, .srt, .translation) }
                                Button(tr("Web subtitles (.vtt)", "웹 자막 (.vtt)")) { export(file, .vtt, .both) }
                                Button(tr("Notes (.md)", "노트 (.md)")) { export(file, .markdown, .both) }
                                switch minutesStatus {
                                case .notOffered:
                                    EmptyView()
                                case .ready:
                                    Divider()
                                    Button(tr("Meeting minutes draft (.md)", "회의록 초안 (.md)")) { writeMinutes(file) }
                                        .disabled(minutesJob != nil)
                                case .unavailable(let reason):
                                    Divider()
                                    Button(tr("Meeting minutes draft (.md)", "회의록 초안 (.md)")) {}.disabled(true)
                                    Text(reason)
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .controlSize(.small)
                        }
                        Button(role: .destructive) { pendingDelete = file } label: { Image(systemName: "trash") }
                            .controlSize(.small)
                            .disabled(minutesJob?.file == file.url)
                            .accessibilityLabel(tr("Delete", "삭제"))
                    }
                }
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .onChange(of: model.scriptFile) { _, _ in reload() }
        .onChange(of: model.status) { _, _ in reload() }
        .alert(tr("Name this meeting", "이 회의에 이름 붙이기"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("For example: Budget meeting", "예: 대책회의"), text: $newName)
            Button(tr("Rename", "이름 바꾸기")) { rename() }
            Button(tr("Cancel", "취소"), role: .cancel) { renaming = nil }
        } message: {
            Text(tr("The transcript and the subtitle files made from it take this name.", "기록과 그 기록에서 만든 자막 파일의 이름이 됩니다."))
        }
        .alert(tr("Could not rename the transcript", "기록의 이름을 바꾸지 못했습니다"), isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })) {
            Button("OK") { renameError = nil }
        } message: {
            Text(renameError ?? "")
        }
        .confirmationDialog(
            tr("Delete this transcript?", "이 기록을 삭제할까요?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(tr("Delete", "삭제"), role: .destructive) {
                if let file = pendingDelete { try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil) }
                pendingDelete = nil
                reload()
            }
            Button(tr("Cancel", "취소"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.url.lastPathComponent ?? "")
        }
    }

    private func rename() {
        guard let file = renaming else { return }
        renaming = nil
        do {
            if let renamed = try TranscriptFiles.rename(file.url, to: newName), file.url == model.scriptFile { model.transcriptMoved(to: renamed) }
        } catch {
            renameError = error.localizedDescription
        }
        reload()
    }

    /// Writes the transcript as subtitles or notes next to the original and shows it in Finder.
    private func export(_ file: TranscriptFile, _ format: TranscriptExport.Format, _ content: TranscriptExport.Content) {
        do {
            let text = try String(contentsOf: file.url, encoding: .utf8)
            let base = file.url.deletingPathExtension()
            var destination = base.appendingPathExtension(format.fileExtension)
            var number = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = URL(fileURLWithPath: base.path + "-\(number)").appendingPathExtension(format.fileExtension)
                number += 1
            }
            let script = ScriptParser.parse(text)
            try TranscriptExport.render(script, format: format, content: content, title: base.lastPathComponent)
                .write(to: destination, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Could not export the transcript", "기록을 내보내지 못했습니다")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// The language the minutes are written in: the one the person reads, else the one that was heard.
    private var minutesLanguage: SpokenLanguage { model.setup.shown ?? model.setup.heard }

    private var minutesStatus: MinutesGenerator.Status { MinutesGenerator.status(for: minutesLanguage) }

    /// Writes `<name>-minutes.md` next to the transcript with the on-device language model, and shows it in Finder.
    private func writeMinutes(_ file: TranscriptFile) {
        guard #available(macOS 26.0, *), minutesJob == nil else { return }
        let language = minutesLanguage
        let url = file.url
        var job = MinutesJob(file: url)
        job.task = Task {
            defer { minutesJob = nil }
            do {
                let script = ScriptParser.parse(try String(contentsOf: url, encoding: .utf8))
                guard !script.entries.isEmpty else { throw MinutesError(errorDescription: tr("This transcript has no sentences.", "이 기록에는 문장이 없습니다.")) }
                let minutes = try await MinutesGenerator.generate(entries: script.entries, language: language) { done, total in
                    await MainActor.run { minutesJob?.done = done; minutesJob?.total = total }
                }
                try Task.checkCancellation()
                let destination = try TranscriptFiles.writeMinutes(minutes, entries: script.entries, transcript: url, language: language)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let alert = NSAlert()
                alert.messageText = tr("Could not write the minutes", "회의록 초안을 만들지 못했습니다")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        minutesJob = job
    }

    private func reload() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: Preferences.scriptDirectory, includingPropertiesForKeys: keys)) ?? []
        files = urls.filter { $0.pathExtension == "txt" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return TranscriptFile(url: url, modified: values?.contentModificationDate ?? .distantPast, bytes: values?.fileSize ?? 0)
        }.sorted { $0.modified > $1.modified }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = tr("Choose", "선택")
        panel.directoryURL = Preferences.scriptDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.setScriptDirectory(url)
            reload()
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    let updater: Updater
    let openSetup: () -> Void
    let openWhatsNew: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Ieum").font(.system(size: 22, weight: .semibold))
            Text(tr("Ieum (이음) means \"to connect\": English and Korean, in the same meeting.",
                    "이음: 영어와 한국어를 한 회의 안에서 이어 줍니다."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(tr("Version \(version)", "버전 \(version)")).foregroundStyle(.secondary)
            Text(tr("Live captions and translation for meetings. Speech recognition and translation run on this Mac. No account, no cloud: your voice and your transcripts never leave this computer.",
                    "회의용 실시간 자막과 번역입니다. 음성 인식과 번역이 이 Mac 안에서 처리됩니다. 계정도 클라우드도 없으며 음성과 기록은 이 컴퓨터 밖으로 나가지 않습니다."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button(tr("Check for updates…", "업데이트 확인…")) { updater.checkNow() }
                Button(tr("What's new…", "새로운 기능…"), action: openWhatsNew)
                Button(tr("Permissions and setup…", "권한 및 설정 점검…"), action: openSetup)
            }
            Spacer()
        }
        .padding(28)
    }
}
