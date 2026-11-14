import CaptionCore
import SwiftUI

/// Four small bars that move with the sound: the quickest way to see that the microphone hears something.
struct LevelMeter: View {
    let level: Float
    let palette: Theme.Palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                let lit = level > Float(index) / 4 + 0.05
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? Theme.live : palette.interim.opacity(0.35))
                    .frame(width: 3, height: CGFloat(5 + index * 3))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// When the sound itself is the problem (silence, too far, too loud), say so in the panel and offer the fix.
struct SoundCheckBanner: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        if model.status == .listening, let message = model.inputAdvice.message(for: model.source) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.badge.exclamationmark").foregroundStyle(Theme.alert)
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.inputAdvice.suggestsAnotherMicrophone, model.source != .system {
                    PillMenuButton(
                        title: tr("Choose a microphone", "마이크 고르기"), palette: palette, fontSize: 12,
                        tip: tr("Which microphone to listen with", "어느 마이크로 들을지"),
                        accessibility: tr("Choose a microphone", "마이크 고르기"),
                        makeMenu: { [model] in SourceMenu.menu(for: model) }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.alert.opacity(0.14))
        }
    }
}
