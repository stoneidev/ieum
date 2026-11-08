import SwiftUI
import CaptionCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let openSetup: () -> Void
    /// The last tab you used is the one you see next time.
    @AppStorage("settingsTab") private var tab = 0

    var body: some View {
        let _ = model.uiLanguage // follow the language setting
        TabView(selection: $tab) {
            GeneralTab(model: model).tag(0)
                .tabItem { Label(tr("General", "일반"), systemImage: "gearshape") }
            DisplayTab(model: model).tag(1)
                .tabItem { Label(tr("Display", "화면"), systemImage: "captions.bubble") }
            VocabularyTab(model: model).tag(2)
                .tabItem { Label(tr("Vocabulary", "용어집"), systemImage: "text.book.closed") }
            TranscriptsTab(model: model).tag(3)
                .tabItem { Label(tr("Transcripts", "기록"), systemImage: "doc.text") }
            AboutTab(openSetup: openSetup).tag(4)
                .tabItem { Label(tr("About", "정보"), systemImage: "info.circle") }
        }
        .frame(width: 600, height: 760)
    }
}

// MARK: - General

/// One meeting mode: its name and what it does, so the choice explains itself.
private struct ModeRow: View {
    let mode: MeetingMode
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.system(size: 13, weight: .medium))
                    Text(mode.isAvailableOnThisMac ? mode.explanation : tr("Needs macOS 26 or later. Use English → Korean or Korean → English, and swap with ⌃⌥L.", "macOS 26 이상이 필요합니다. 영어 → 한국어나 한국어 → 영어를 쓰고 ⌃⌥L로 방향을 바꾸세요."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!mode.isAvailableOnThisMac)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    private var shortcuts: [(key: String, title: String)] { [
        ("S", tr("Start / stop", "시작/중지")),
        ("H", tr("Show / hide", "보이기/숨기기")),
        ("D", tr("Bar / panel", "바/패널")),
        ("L", tr("Swap English ⇄ Korean", "영어 ⇄ 한국어 방향 바꾸기")),
    ] }

    var body: some View {
        Form {
            Section(tr("Meeting", "회의")) {
                ForEach(MeetingMode.allCases, id: \.self) { mode in
                    ModeRow(mode: mode, selected: mode == model.meetingMode) { model.setMeetingMode(mode) }
                }
                if let warning = model.transcriptWarning {
                    Text(warning).font(.system(size: 12)).foregroundStyle(.orange)
                }

                if model.meetingMode == .captionsOnly {
                    Picker(tr("Caption language", "자막 언어"), selection: Binding(get: { model.captionLanguage }, set: model.setCaptionLanguage)) {
                        ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } else if model.meetingMode != .koreanToEnglish {
                    Picker(tr("English accent", "영어 억양"), selection: Binding(get: { model.englishVariant }, set: model.setEnglishVariant)) {
                        Text(Language.englishUS.title).tag(Language.englishUS)
                        Text(Language.englishAU.title).tag(Language.englishAU)
                    }
                }
                Picker(tr("Audio source", "소리 입력"), selection: Binding(get: { model.source }, set: model.setSource)) {
                    ForEach(Source.allCases, id: \.self) { Text($0.title).tag($0) }
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
                Picker(tr("Interface language", "화면 언어"), selection: Binding(get: { model.uiLanguage }, set: model.setUILanguage)) {
                    Text(tr("Follow the system", "시스템 설정 따르기")).tag("system")
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
            }
        }
        .formStyle(.grouped)
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
                if model.meetingMode.translates {
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
                Toggle(tr("Fade when nobody is speaking", "말이 없으면 흐리게"), isOn: Binding(get: { model.fadeWhenQuiet }, set: model.setFadeWhenQuiet))
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

private struct TranscriptsTab: View {
    @ObservedObject var model: AppModel
    @State private var files: [TranscriptFile] = []
    @State private var pendingDelete: TranscriptFile?

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
                Text(tr("No transcripts yet. Each time you start captions, a new file is saved here.",
                        "아직 기록이 없습니다. 자막을 시작할 때마다 새 파일이 여기에 저장됩니다."))
                    .foregroundStyle(.secondary)
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
                        Button(tr("Show in Finder", "Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.controlSize(.small)
                        Button(role: .destructive) { pendingDelete = file } label: { Image(systemName: "trash") }
                            .controlSize(.small)
                            .accessibilityLabel(tr("Delete", "삭제"))
                    }
                }
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .onChange(of: model.scriptFile) { _, _ in reload() }
        .onChange(of: model.status) { _, _ in reload() }
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
    let openSetup: () -> Void

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
            Button(tr("Permissions and setup…", "권한 및 설정 점검…"), action: openSetup)
            Spacer()
        }
        .padding(28)
    }
}
