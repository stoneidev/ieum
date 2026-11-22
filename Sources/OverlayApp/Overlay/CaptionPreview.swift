import AppKit
import CaptionCore
import SwiftUI

// MARK: - Settings preview

/// The subtitle bar as it will look with the current display settings, over a stand-in for a video call,
/// so size, lines and background can be judged without starting captions.
struct CaptionPreview: View {
    @ObservedObject var model: AppModel

    private static let layoutWidth: CGFloat = 760

    private static func sentence(in language: SpokenLanguage) -> String {
        switch language {
        case .english: "Starting next Monday. The budget is still under review, and we will confirm it by tomorrow. Let us share the schedule today."
        case .korean: "다음 주 월요일부터 시작합니다. 예산은 아직 검토 중이며 내일까지 확정해서 알려드리겠습니다. 일정은 오늘 안에 공유하겠습니다."
        case .japanese: "来週の月曜日から始めます。予算はまだ検討中で、明日までに確定してお知らせします。スケジュールは今日中に共有します。"
        case .chinese: "下周一开始。预算仍在审核中，我们会在明天之前确认。日程今天之内共享。"
        }
    }

    private var sample: (original: String, shown: String, secondary: Bool) {
        let heard = model.setup.heard
        guard let shown = model.setup.shown else { return (Self.sentence(in: heard), Self.sentence(in: heard), false) }
        return (Self.sentence(in: heard), Self.sentence(in: shown), model.translationLayout == .both)
    }

    var body: some View {
        let palette = Theme.palette(for: model.background)
        let size = model.textSize.points
        let content = sample
        let fontSize = size * ScriptScale.factor(for: content.shown)
        let pitch = BarMetrics.fontLineHeight(size) + BarMetrics.lineSpacing(size)
        let barHeight = BarMetrics.height(lines: model.barLines, size: size, secondaryRow: content.secondary)
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.layoutWidth
            ZStack(alignment: .bottom) {
                backdrop
                VStack(alignment: .leading, spacing: BarMetrics.secondaryGap) {
                    if content.secondary {
                        Text(content.original)
                            .font(.system(size: BarMetrics.secondarySize(size) * ScriptScale.factor(for: content.original, hangulScale: 0.92)))
                            .foregroundStyle(palette.interim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 25)
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        StatusDot(status: .listening, idleColor: palette.interim)
                            .padding(.bottom, max(0, (BarMetrics.fontLineHeight(fontSize) - 9) / 2))
                        Text(content.shown)
                            .font(.system(size: fontSize, weight: .medium))
                            .lineSpacing(pitch - BarMetrics.fontLineHeight(fontSize))
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxHeight: BarMetrics.textHeight(lines: model.barLines, size: size), alignment: .bottomLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .clipped()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, BarMetrics.horizontalPadding)
                .padding(.vertical, BarMetrics.verticalPadding)
                .frame(width: Self.layoutWidth, height: barHeight)
                .background { barBackground(palette) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(palette.border, lineWidth: 0.5) }
                .preferredColorScheme(palette.scheme)
                .scaleEffect(scale, anchor: .bottom)
                .frame(width: geometry.size.width, height: barHeight * scale, alignment: .bottom)
                .padding(.bottom, 14)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Preview of the subtitle bar", "자막 바 미리보기"))
    }

    /// A stand-in for a video call behind the bar, so the effect of the opacity is visible.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.28, blue: 0.34), Color(red: 0.12, green: 0.14, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(index == 1 ? 0.16 : 0.09))
                        .overlay(Image(systemName: "person.fill").font(.system(size: 34)).foregroundStyle(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    private func barBackground(_ palette: Theme.Palette) -> some View {
        switch model.background {
        case .glass, .light:
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(model.backgroundOpacity)
                palette.tint.opacity(model.backgroundOpacity)
            }
        case .solid, .black:
            palette.tint.opacity(model.backgroundOpacity)
        }
    }
}
