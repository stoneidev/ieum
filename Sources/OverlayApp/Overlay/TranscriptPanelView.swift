import AppKit
import CaptionCore
import SwiftUI

// MARK: - Transcript panel

struct TranscriptPanelView: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Body text follows the chosen text size, but stays in a range that suits a scrolling list.
    private var bodySize: CGFloat { max(14, (model.textSize.points * 0.57).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.ink.opacity(0.10))
            SoundCheckBanner(model: model, palette: palette)
            StartSuggestionBanner(model: model, palette: palette)
            PausedBanner(model: model, palette: palette)
            if model.panelPage == .minutes, model.offersMinutes {
                MinutesPanelView(model: model, palette: palette, bodySize: bodySize)
            } else {
                conversation
                wrapUp
            }
            VocabularyCard(model: model, palette: palette)
            // One ask at a time: the coffee waits until the words are answered.
            if !model.vocabularyCardOpen { CoffeeCard(model: model, palette: palette) }
        }
    }

    /// Starts a new conversation: what was said is already saved in its file.
    private var newConversationButton: some View {
        Button(action: { model.startNewConversation() }) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil").font(.system(size: 11, weight: .semibold))
                Text(tr("New conversation", "새 대화")).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.interim.opacity(0.22)))
            .overlay(Capsule().strokeBorder(palette.ink.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(tr("Save this conversation and start a new one. Nothing is deleted: it stays in Settings > Transcripts.",
                 "이 대화를 저장해 두고 새로 시작합니다. 아무것도 지워지지 않고 설정 > 기록에 남습니다."))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if !(model.finalizedLines.isEmpty && model.partial.isEmpty) {
                HStack {
                    Spacer(minLength: 0)
                    newConversationButton
                }
                .padding(.horizontal, 8)
                Divider().overlay(palette.ink.opacity(0.08))
            }
            conversationList
        }
    }

    private var conversationList: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.finalizedLines.isEmpty && model.partial.isEmpty {
                            if model.isRunning {
                                Text(emptyMessage)
                                    .font(.system(size: bodySize - 2))
                                    .foregroundStyle(palette.interim)
                                    .padding(.top, 6)
                            } else {
                                SituationPicker(model: model, palette: palette)
                                    .padding(.top, 4)
                                Text(emptyMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.interim)
                            }
                        }
                        ForEach(model.finalizedLines) { line in
                            // A line keeps its translation after captions stop; only lines that never got one show the original.
                            if let translation = line.displayTranslation {
                                row(
                                    time: Self.timeFormatter.string(from: line.time),
                                    text: translation,
                                    color: line.translation == nil ? palette.interim : palette.ink,
                                    original: model.translationLayout == .both ? line.text : nil,
                                    language: line.language, speaker: line.speaker, translated: true
                                )
                            } else {
                                row(time: Self.timeFormatter.string(from: line.time), text: line.text, color: palette.ink, original: nil, language: line.language, speaker: line.speaker)
                            }
                        }
                        if !model.partial.isEmpty {
                            if model.translationActive, !model.translatedPartial.isEmpty {
                                row(time: "·  ·  ·", text: model.translatedPartial, color: palette.interim,
                                    original: model.translationLayout == .both ? model.partial : nil, language: model.partialLanguage, speaker: model.partialSpeaker, translated: true)
                            } else {
                                row(time: "·  ·  ·", text: model.partial, color: palette.interim, original: nil, language: model.partialLanguage, speaker: model.partialSpeaker)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.finalizedLines.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.partial) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
    }

    /// After the meeting: where the minutes are and how to get them.
    @ViewBuilder
    private var wrapUp: some View {
        if model.offersMinutes, model.canMakeMinutes {
            Divider().overlay(palette.ink.opacity(0.10))
            Button(action: { model.showMinutes(start: false) }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                    Text(model.minutesState == .ready
                         ? (model.minutesScenario ?? model.scenario).notesTitle + tr(" is ready", " 초안이 준비되었습니다")
                         : model.scenario.endedPrompt)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The controls on the right keep their size; in a narrow panel the languages give way first, then the situation pill.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(chip: true, languages: .full)
            headerRow(chip: true, languages: .compact)
            headerRow(chip: false, languages: .compact)
            headerRow(chip: false, languages: .none)
        }
    }

    private enum HeaderLanguages { case full, compact, none }

    private func headerRow(chip: Bool, languages: HeaderLanguages) -> some View {
        HStack(spacing: 8) {
            StatusDot(status: model.status, idleColor: palette.interim)
            if model.status == .listening { LevelMeter(level: model.inputLevel, palette: palette) }
            if chip { SituationChip(model: model, palette: palette) }
            if languages != .none {
                LanguageRouteChip(model: model, palette: palette, compact: languages == .compact)
                    .help(model.activeSetup.explanation + "\n" + model.source.title)
            }
            Spacer(minLength: 8)
            if model.status == .idle {
                StartCaptionsButton(model: model, fontSize: 13)
            } else if model.status == .listening, model.translationNotice == nil {
                Button(action: { model.toggleRunning() }) {
                    HStack(spacing: 6) {
                        Text(tr("Stop", "중지")).font(.system(size: 13, weight: .medium))
                        if model.globalShortcuts {
                            Text("⌃⌥S").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.6)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(palette.ink.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint(tr("Stops live captions and saves the transcript", "실시간 자막을 멈추고 기록을 저장합니다"))
            } else if let notice = model.translationNotice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.alert)
                    .lineLimit(2)
            } else if case .error(let message) = model.status {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.alert)
                    .lineLimit(2)
            }
            ReplyButton(model: model, palette: palette)
            DisplayToggleButton(model: model, palette: palette)
            OverlayMenuButton(model: model, palette: palette)
            QuitButton(model: model, palette: palette)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// One sentence. The language that was spoken is labeled and comes first (small, muted); its translation is labeled
    /// too and is the main text, so the two never read as one mixed block.
    private func row(time: String, text: String, color: Color, original: String?, language: String, speaker: Speaker?, translated: Bool = false) -> some View {
        let spoken = language.isEmpty ? model.activeSetup.heard.code : language
        let target = model.translationLanguage(forSpoken: spoken)
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.system(size: max(11, (bodySize * 0.72).rounded()), weight: .regular).monospacedDigit())
                    .foregroundStyle(palette.interim)
                if let speaker {
                    SpeakerChip(speaker: speaker, palette: palette, size: 10)
                }
            }
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if let original {
                    labeled(spoken, show: true) {
                        Text(original)
                            .font(.system(size: max(12, bodySize - 4), weight: .regular))
                            .foregroundStyle(palette.interim)
                            .textSelection(.enabled)
                    }
                }
                labeled(translated ? target : spoken, show: translated || model.activeSetup.isConversation) {
                    Text(text)
                        .font(.system(size: bodySize * ScriptScale.factor(for: text, hangulScale: ScriptScale.hangulPanel), weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(color)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A line of text with its language tag in front, so the spoken sentence and its translation are told apart.
    @ViewBuilder
    private func labeled<Content: View>(_ language: String?, show: Bool, @ViewBuilder content: () -> Content) -> some View {
        if show, let language, !language.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LanguageChip(language: language, palette: palette, size: 9)
                    .frame(width: 30, alignment: .leading)
                content()
            }
        } else {
            content()
        }
    }

    private var emptyMessage: String {
        model.isRunning
            ? tr("Listening. Sentences appear here as they are finished.", "듣고 있습니다. 문장이 끝나면 여기에 쌓입니다.")
            : tr("Captions are off. Finished sentences will be listed here with their time.", "자막이 꺼져 있습니다. 시작하면 끝난 문장이 시각과 함께 여기에 쌓입니다.")
    }
}
