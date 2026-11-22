import SwiftUI

/// The coffee ask after a finished meeting, as a quiet card at the bottom of the transcript panel.
struct CoffeeCard: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        if model.coffeeThanks {
            thanks
        } else if model.coffeeStage != nil, !model.isRunning {
            ask
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.coffeeTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(model.coffeeBody)
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                CoffeeButton(title: "☕ " + tr("Buy a coffee", "커피 사주기"), prominent: true, palette: palette) { model.openCoffeePage() }
                CoffeeButton(title: tr("Not now", "나중에"), prominent: false, palette: palette) { model.postponeCoffee() }
                CoffeeButton(title: tr("Do not ask again", "그만 보기"), prominent: false, palette: palette) { model.declineCoffee() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.interim.opacity(0.10))
    }

    private var thanks: some View {
        HStack(spacing: 8) {
            Text("☕")
            Text(tr("Thank you! The next meeting gets captioned with extra care.", "고마워요! 다음 회의는 더 정성껏 받아 적을게요."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 4)
            Button(action: { model.dismissThanks() }) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.interim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Close", "닫기"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.interim.opacity(0.10))
    }
}

struct CoffeeButton: View {
    let title: String
    let prominent: Bool
    let palette: Theme.Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(palette.interim.opacity(prominent ? 0.30 : 0.12)))
                .overlay(Capsule().strokeBorder(palette.ink.opacity(prominent ? 0.45 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
