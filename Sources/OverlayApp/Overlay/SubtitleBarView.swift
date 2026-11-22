import AppKit
import CaptionCore
import SwiftUI

// MARK: - Subtitle bar


struct SubtitleBarView: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    /// What the bar says right now: `confirmed` in full contrast, `tentative` muted.
    private struct Caption {
        var confirmed = ""
        var tentative = ""
        var plain: String { confirmed + tentative }
    }

    var body: some View {
        if model.status == .idle {
            idleBar
        } else {
            liveBar
        }
    }

    /// Captions are off: one calm line with the way to turn them on, instead of an empty multi-line bar.
    private var idleBar: some View {
        let size = model.textSize.points
        let fontSize = max(15, (size * 0.6).rounded())
        // When the coffee ask is up and the bar is narrow, it shrinks to the ☕ button so the controls on the right stay reachable.
        // The situation chip and the words give way, in this order, as the bar gets narrower; the controls on the right never do.
        return ViewThatFits(in: .horizontal) {
            idleRow(fontSize: fontSize, ask: .full, chip: true, languages: true, sound: true)
            idleRow(fontSize: fontSize, ask: .full, chip: true, languages: true, sound: false)
            idleRow(fontSize: fontSize, ask: .compact, chip: true, languages: true, sound: false)
            idleRow(fontSize: fontSize, ask: .compact, chip: true, languages: false, sound: false)
            idleRow(fontSize: fontSize, ask: .compact, chip: false, languages: false, sound: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, BarMetrics.horizontalPadding)
        .padding(.vertical, BarMetrics.verticalPadding)
    }

    private enum AskLayout { case full, compact }

    private func idleRow(fontSize: CGFloat, ask: AskLayout, chip: Bool, languages: Bool, sound: Bool) -> some View {
        HStack(spacing: 14) {
            StatusDot(status: .idle, idleColor: palette.interim)
            if chip { SituationChip(model: model, palette: palette, fontSize: max(12, fontSize - 4)) }
            if languages { LanguageRouteChip(model: model, palette: palette, fontSize: max(12, fontSize - 4)) }
            if sound { SourceChip(model: model, palette: palette, fontSize: max(12, fontSize - 4)) }
            if model.coffeeThanks {
                Text("☕ " + tr("Thank you!", "고마워요!"))
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            } else if model.coffeeStage != nil {
                if ask == .full {
                    Text(model.coffeeTitle)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                CoffeeButton(title: ask == .full ? "☕ " + tr("Buy a coffee", "커피 사주기") : "☕", prominent: true, palette: palette) { model.openCoffeePage() }
                    .help(tr("Buy me a coffee", "커피 한 잔 사주기"))
                Button(action: { model.postponeCoffee() }) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.interim)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Not now", "나중에"))
                .accessibilityLabel(tr("Not now", "나중에"))
            } else if ask == .full {
                if let app = model.startSuggestion {
                    Text(tr("\(app.name) is open. Start captions?", "\(app.name) 사용 중 · 자막을 켤까요?"))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Button(action: { model.dismissStartSuggestion() }) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.interim)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Not now", "나중에"))
                    .accessibilityLabel(tr("Not now", "나중에"))
                } else {
                    Text(tr("Captions are off", "자막이 꺼져 있습니다"))
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(palette.interim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: 12)
            StartCaptionsButton(model: model, fontSize: fontSize)
            BarControls(model: model, palette: palette, subdued: false)
        }
    }

    @ViewBuilder
    private var liveBar: some View {
        let size = model.textSize.points
        let caption = currentCaption
        // Line pitch is fixed by the chosen size, so the bar height never depends on the language. A smaller
        // Hangul font keeps the same pitch and simply gets more leading.
        let pitch = BarMetrics.fontLineHeight(size) + BarMetrics.lineSpacing(size)
        let fontSize = size * ScriptScale.factor(for: caption.plain)
        let textHeight = BarMetrics.textHeight(lines: model.barLines, size: size)
        VStack(alignment: .leading, spacing: BarMetrics.secondaryGap) {
            if model.showsSecondaryRow { secondaryRow(size: size) }
            HStack(alignment: .bottom, spacing: 16) {
                StatusDot(status: model.status, idleColor: palette.interim)
                    .padding(.bottom, max(0, (BarMetrics.fontLineHeight(fontSize) - 9) / 2))
                    .help(tr("Drag here to move the bar. It stays solid at this end.", "여기를 끌어 자막 바를 옮기세요. 이 쪽 끝에서는 바가 흐려지지 않습니다."))
                // The text block is as tall as its content up to the chosen number of lines, anchored at the
                // bottom and clipped at the top, so older lines scroll out whole and never half-cut.
                text(caption)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineSpacing(pitch - BarMetrics.fontLineHeight(fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: textHeight, alignment: .bottomLeading)
                    // A flexible frame grows to whatever space it is offered; pin it to its content height
                    // (capped at `textHeight`) so a short caption does not leave a gap under the original row.
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                    .animation(.easeOut(duration: 0.25), value: model.barFinalText)
                    .animation(.easeOut(duration: 0.25), value: model.barTranslation.confirmed)
                BarControls(model: model, palette: palette, subdued: true)
                    .padding(.bottom, max(0, (BarMetrics.fontLineHeight(fontSize) - 28) / 2))
            }
        }
        // The window is fixed-height; the original row and the text sit together at the bottom of it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, BarMetrics.horizontalPadding)
        .padding(.vertical, BarMetrics.verticalPadding)
    }

    private func text(_ caption: Caption) -> Text {
        let separator = TextScript.joiner(between: caption.confirmed, and: caption.tentative)
        return Text(caption.confirmed).foregroundColor(palette.ink)
            + Text(separator + caption.tentative).foregroundColor(palette.interim)
    }

    /// The speaker's own words, small and quiet, so the translation stays the thing you read.
    /// When translation cannot run, this row says why instead.
    private func secondaryRow(size: CGFloat) -> some View {
        let shown = model.translationNotice == nil && !showsOriginalAsMain ? originalLine : ""
        let small = BarMetrics.secondarySize(size) * ScriptScale.factor(for: shown, hangulScale: 0.92)
        return HStack(spacing: 8) {
            if model.translationNotice == nil, let speaker = originalSpeaker {
                SpeakerChip(speaker: speaker, palette: palette, size: max(10, small - 4))
            } else if model.translationNotice == nil, model.setup.isConversation, !originalLanguage.isEmpty {
                LanguageChip(language: originalLanguage, palette: palette, size: max(10, small - 4))
            }
            Group {
                if let notice = model.translationNotice {
                    Text(notice).foregroundStyle(Theme.alert)
                } else if !showsOriginalAsMain {
                    // The transcript arrives first: keep it readable from across the table, not just a caption of the caption.
                    Text(originalLine).foregroundStyle(palette.ink.opacity(0.74))
                }
            }
            .font(.system(size: small, weight: .regular))
            .lineLimit(1)
            .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, minHeight: BarMetrics.secondaryHeight(size) - BarMetrics.secondaryGap, alignment: .leading)
        .padding(.leading, 25)
    }

    /// The translation has not arrived yet, so the original is the large line (and not repeated in the small row).
    private var showsOriginalAsMain: Bool {
        model.status == .listening && model.translationActive && model.translationNotice == nil
            && model.barTranslation.confirmed.isEmpty && model.barTranslation.tentative.isEmpty
            && !originalLine.isEmpty
    }

    private var originalSpeaker: Speaker? {
        model.partial.isEmpty ? model.finalizedLines.last?.speaker : model.partialSpeaker
    }

    private var originalLanguage: String {
        model.partial.isEmpty ? (model.finalizedLines.last?.language ?? "") : model.partialLanguage
    }

    /// Newest words of the original: the sentence being spoken, else the last finished one.
    private var originalLine: String {
        model.partial.isEmpty ? model.barFinalText : model.partial
    }

    private var currentCaption: Caption {
        if model.isPaused, model.status == .listening {
            return Caption(tentative: tr("Paused. Nothing is being written down.", "일시정지 중입니다. 지금 하는 말은 기록하지 않습니다.") + (model.globalShortcuts ? "  ⌃⌥P" : ""))
        }
        switch model.status {
        case .error(let message):
            return Caption(confirmed: message)
        case .idle:
            return Caption()
        case .starting:
            return Caption(tentative: model.startingNote ?? tr("Starting…", "시작하는 중…"))
        case .listening where model.translationActive:
            let t = model.barTranslation
            if t.confirmed.isEmpty && t.tentative.isEmpty {
                // Nothing translated yet: show what was heard, muted, until its translation arrives.
                if showsOriginalAsMain { return Caption(tentative: originalLine) }
                return Caption(tentative: model.inputAdvice.message(for: model.source) ?? tr("Listening…", "듣는 중…"))
            }
            return Caption(confirmed: t.confirmed, tentative: t.tentative)
        case .listening:
            if model.barFinalText.isEmpty && model.partial.isEmpty {
                return Caption(tentative: model.inputAdvice.message(for: model.source) ?? tr("Listening…", "듣는 중…"))
            }
            return Caption(confirmed: model.barFinalText, tentative: TextScript.joiner(between: model.barFinalText, and: model.partial) + model.partial)
        }
    }
}
