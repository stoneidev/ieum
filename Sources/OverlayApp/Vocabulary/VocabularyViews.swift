import CaptionCore
import SwiftUI

/// After a meeting: the names and product words that came up and are not in the vocabulary, one tap each.
struct VocabularyCard: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        if model.vocabularyCardOpen, !model.isRunning {
            if model.vocabularySuggestions.isEmpty { thanks } else { ask }
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("These came up. Spell them right next time?", "이런 말이 나왔어요. 다음엔 정확히 받아 적을까요?"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(tr("Tap a word to add it to your vocabulary. Ieum then fixes it in the captions and in the translation.",
                    "단어를 누르면 용어집에 들어갑니다. 그러면 자막과 번역에서 이 철자로 바로잡아 줍니다."))
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(model.vocabularySuggestions, id: \.self) { term in
                    CoffeeButton(title: "+ " + term, prominent: true, palette: palette) { model.addSuggestedTerm(term) }
                }
            }
            HStack(spacing: 8) {
                if model.vocabularySuggestions.count > 1 {
                    CoffeeButton(title: tr("Add all", "모두 추가"), prominent: false, palette: palette) { model.addAllSuggestedTerms() }
                }
                CoffeeButton(title: tr("Not now", "나중에"), prominent: false, palette: palette) { model.dismissVocabularyCard() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.interim.opacity(0.10))
    }

    private var thanks: some View {
        HStack(spacing: 8) {
            Text("✓")
            Text(tr("Added \(model.vocabularyAdded). They are spelled right from the next sentence.",
                    "\(model.vocabularyAdded)개를 추가했어요. 다음 문장부터 정확하게 받아 적어요."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 4)
            Button(action: { model.dismissVocabularyCard() }) {
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

/// Before the first meeting that has a vocabulary: why it is worth two minutes, and a way in.
struct VocabularyTip: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        if model.showsVocabularyTip {
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 " + tr("Names get misheard. Teach Ieum yours.", "이름은 잘못 들리기 쉬워요. 이음에게 알려 주세요."))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(tr("Put in the people, products and company words of today's meeting, and \"R. Q. Bernates\" becomes \"Kubernetes\" in the captions and the translation. Two minutes now saves every meeting after.",
                        "오늘 회의의 사람, 제품, 회사 용어를 넣어 두면 자막과 번역에서 \"R. Q. Bernates\"가 \"Kubernetes\"로 바로잡혀요. 지금 2분이면 앞으로 모든 회의가 편해집니다."))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.interim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CoffeeButton(title: tr("Add words", "용어 추가"), prominent: true, palette: palette) { model.openVocabularySettings() }
                    CoffeeButton(title: tr("Don't show again", "다시 보지 않기"), prominent: false, palette: palette) { model.dismissVocabularyTip() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.interim.opacity(0.10)))
        }
    }
}
