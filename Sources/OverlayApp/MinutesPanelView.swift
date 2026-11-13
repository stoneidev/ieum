import AppKit
import CaptionCore
import SwiftUI

/// The "Minutes" view of the transcript panel: what the minutes are, how to get them, and the draft itself with the
/// transcript lines each point rests on.
struct MinutesPanelView: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    let bodySize: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.minutesState {
        case .working(let done, let total):
            working(done: done, total: total)
        case .ready:
            if let minutes = model.minutes { draft(minutes) }
        case .failed(let message):
            note(title: tr("Could not write the draft", "초안을 만들지 못했습니다"), text: message)
            if model.canMakeMinutes { button(tr("Try again", "다시 시도"), prominent: true) { model.makeMinutes() } }
        case .idle:
            idle
        }
    }

    // MARK: States

    @ViewBuilder
    private var idle: some View {
        if model.isRunning {
            note(title: model.scenario.stillGoing,
                 text: tr("Stop the captions when it is over, and the \(model.scenario.notesTitle.lowercased()) can be written from it here. Until then, the Conversation tab shows what is being said.",
                          "끝나서 자막을 멈추면 여기서 \(model.scenario.notesTitle) 초안을 만들 수 있습니다. 그때까지는 '대화' 탭에서 지금 오가는 말을 보세요."))
            button(tr("Show the conversation", "대화 보기"), prominent: false) { model.panelTab = .conversation }
        } else if !model.canMakeMinutes {
            note(title: model.scenario.nothingYet,
                 text: tr("Start the captions. When it is over, the \(model.scenario.notesTitle.lowercased()) draft is made here from what was said.",
                          "자막을 시작하세요. 끝나면 오간 말로 여기서 \(model.scenario.notesTitle) 초안을 만듭니다."))
        } else {
            note(title: model.scenario.notesTitle + tr(" draft", " 초안"),
                 text: tr("\(model.scenario.contents.prefix(1).uppercased() + model.scenario.contents.dropFirst()), written on this Mac from the transcript. Every point shows the lines it comes from, so you can check it. Nothing leaves your Mac.",
                          "이 기록으로 \(model.scenario.contents)을(를) 이 Mac 안에서 씁니다. 항목마다 근거가 된 줄이 함께 나오므로 확인할 수 있습니다. 내용은 Mac 밖으로 나가지 않습니다."))
            switch model.minutesStatus {
            case .ready:
                button(tr("Write the draft", "초안 만들기"), prominent: true) { model.makeMinutes() }
                Text(tr("It takes from a few seconds to a couple of minutes, depending on the length.", "길이에 따라 몇 초에서 몇 분이 걸립니다."))
                    .font(.system(size: 12)).foregroundStyle(palette.interim)
            case .unavailable(let reason):
                Text(reason).font(.system(size: 13)).foregroundStyle(Theme.alert)
            case .notOffered:
                EmptyView()
            }
        }
    }

    private func working(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Reading the meeting…", "회의 내용을 읽는 중…"))
                .font(.system(size: bodySize, weight: .semibold)).foregroundStyle(palette.ink)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text(total > 1 ? tr("Part \(min(done + 1, total)) of \(total)", "\(total)부분 중 \(min(done + 1, total))번째") : tr("This takes a moment.", "잠시 걸립니다."))
                .font(.system(size: 12)).foregroundStyle(palette.interim)
            button(tr("Stop", "중지"), prominent: false) { model.cancelMinutes() }
        }
    }

    // MARK: The draft

    @ViewBuilder
    private func draft(_ minutes: MeetingMinutes) -> some View {
        Text(tr("A draft written by a language model on this Mac. Check each point against the lines it cites before you rely on it.",
                "이 Mac의 언어 모델이 쓴 초안입니다. 믿고 쓰기 전에 항목마다 근거 줄과 맞는지 확인하세요."))
            .font(.system(size: 12)).foregroundStyle(palette.interim)

        let language = model.minutesWrittenIn ?? model.minutesLanguage
        ForEach(model.minutesTemplateSections, id: \.self) { kind in
            section(MinutesMarkdown.heading(kind, language: language)) {
                if kind == .summary {
                    summary(minutes)
                } else {
                    points(MinutesMarkdown.points(kind, in: minutes))
                }
            }
        }

        HStack(spacing: 8) {
            button(tr("Copy", "복사"), prominent: false) {
                if let text = model.minutesMarkdown {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            if let file = model.minutesFile {
                button(tr("Show in Finder", "Finder에서 보기"), prominent: false) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            button(tr("Write again", "다시 만들기"), prominent: false) { model.makeMinutes() }
        }
        if let file = model.minutesFile {
            Text(tr("Saved as \(file.lastPathComponent) next to the transcript.", "기록 옆에 \(file.lastPathComponent)로 저장되었습니다."))
                .font(.system(size: 11)).foregroundStyle(palette.interim)
        }
    }

    @ViewBuilder
    private func summary(_ minutes: MeetingMinutes) -> some View {
        if minutes.parts.isEmpty {
            Text(tr("None found.", "찾지 못했습니다.")).foregroundStyle(palette.interim)
        }
        ForEach(Array(minutes.parts.enumerated()), id: \.offset) { _, part in
            VStack(alignment: .leading, spacing: 2) {
                Text(part.summary).foregroundStyle(palette.ink)
                if minutes.parts.count > 1 {
                    Text(tr("lines \(part.lines.lowerBound)–\(part.lines.upperBound)", "\(part.lines.lowerBound)–\(part.lines.upperBound)번째 줄"))
                        .font(.system(size: 11)).foregroundStyle(palette.interim)
                }
            }
        }
    }

    @ViewBuilder
    private func points(_ items: [MeetingMinutes.Point]) -> some View {
        if items.isEmpty {
            Text(tr("None found.", "찾지 못했습니다.")).foregroundStyle(palette.interim)
        }
        ForEach(Array(items.enumerated()), id: \.offset) { _, point in
            VStack(alignment: .leading, spacing: 2) {
                Text(point.displayText).foregroundStyle(palette.ink).textSelection(.enabled)
                if point.lines.isEmpty {
                    Text("⚠︎ " + tr("no source line", "근거 줄 없음")).font(.system(size: 11)).foregroundStyle(Theme.alert)
                } else {
                    Text(tr("from ", "근거: ") + citation(point.lines)).font(.system(size: 11)).foregroundStyle(palette.interim)
                }
            }
        }
    }

    /// `[4] 00:01:02, [5] 00:01:20`: the line number in the transcript and when it was said.
    private func citation(_ lines: [Int]) -> String {
        lines.prefix(4).map { number -> String in
            guard model.minutesEntries.indices.contains(number - 1) else { return "[\(number)]" }
            return "[\(number)] " + TranscriptExport.timecode(model.minutesEntries[number - 1].offset, comma: false).prefix(8)
        }.joined(separator: ", ") + (lines.count > 4 ? " …" : "")
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: bodySize, weight: .semibold)).foregroundStyle(palette.ink)
            content()
        }
        .font(.system(size: max(13, bodySize - 1)))
    }

    private func note(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: bodySize, weight: .semibold)).foregroundStyle(palette.ink)
            Text(text).font(.system(size: max(13, bodySize - 1))).foregroundStyle(palette.interim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(palette.interim.opacity(prominent ? 0.30 : 0.14)))
                .overlay(Capsule().strokeBorder(palette.ink.opacity(prominent ? 0.45 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
