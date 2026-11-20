import CaptionCore
import SwiftUI

/// A volume icon whose waves light up with the sound: it reads as "how loud is it", not as a radio signal.
struct LevelMeter: View {
    let level: Float
    let palette: Theme.Palette

    var body: some View {
        Image(systemName: "speaker.wave.3", variableValue: Double(level))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(level > 0.05 ? Theme.live : palette.interim.opacity(0.6))
            .frame(width: 20, height: 16)
            .animation(.easeOut(duration: 0.12), value: level)
            .help(tr("How loud the sound is that reaches Ieum", "이음에 들어오는 소리의 크기"))
            .accessibilityLabel(tr("Sound level", "소리 크기"))
    }
}

/// A meeting app came to the front and the captions are off: one question, three answers.
struct StartSuggestionBanner: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        if let app = model.startSuggestion, !model.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("\(app.name) is open. Start the captions?", "\(app.name)을(를) 쓰고 있네요. 자막을 켤까요?"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                HStack(spacing: 8) {
                    CoffeeButton(title: tr("Start captions", "자막 시작"), prominent: true, palette: palette) { model.acceptStartSuggestion() }
                    CoffeeButton(title: tr("Not now", "나중에"), prominent: false, palette: palette) { model.dismissStartSuggestion() }
                    CoffeeButton(title: tr("Don't ask for \(app.name)", "\(app.name)은(는) 묻지 않기"), prominent: false, palette: palette) { model.muteStartSuggestion() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.live.opacity(0.14))
        }
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
