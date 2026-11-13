import AppKit
import CaptionCore
import SwiftUI

/// The situation (conversation, meeting, seminar) where it is used: a small pill on the bar and the panel that opens the
/// choice, so it is set right before the captions start instead of deep in the settings.
struct SituationChip: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSButton {
        let button = ChipButton()
        button.isBordered = false
        button.wantsLayer = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.show(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setAccessibilityRole(.popUpButton)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        let ink = NSColor(palette.ink)
        let title = NSMutableAttributedString(string: model.scenario.chipTitle + " ", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: ink,
        ])
        title.append(NSAttributedString(string: "▾", attributes: [.font: NSFont.systemFont(ofSize: fontSize - 2), .foregroundColor: ink.withAlphaComponent(0.7)]))
        button.attributedTitle = title
        button.layer?.cornerRadius = (fontSize + 10) / 2
        button.layer?.backgroundColor = NSColor(palette.interim).withAlphaComponent(0.20).cgColor
        button.toolTip = tr("What are you doing? ", "지금 무엇을 하시나요? ") + model.scenario.hint
        button.setAccessibilityLabel(tr("Situation: ", "상황: ") + model.scenario.title)
        context.coordinator.model = model
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let size = nsView.attributedTitle.size()
        return CGSize(width: ceil(size.width) + 22, height: fontSize + 10)
    }

    private final class ChipButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: AppModel
        init(model: AppModel) { self.model = model }

        @objc func show(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let header = NSMenuItem(title: tr("What are you doing?", "지금 무엇을 하시나요?"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for scenario in Scenario.allCases {
                let item = ScenarioItem(scenario: scenario, model: model)
                item.state = scenario == model.scenario ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 2 : -2), in: sender)
        }
    }

    private final class ScenarioItem: NSMenuItem {
        private let scenario: Scenario
        private let model: AppModel

        @MainActor
        init(scenario: Scenario, model: AppModel) {
            self.scenario = scenario
            self.model = model
            super.init(title: scenario.title + "  ·  " + scenario.hint, action: #selector(choose), keyEquivalent: "")
            target = self
            image = NSImage(systemSymbolName: scenario.symbol, accessibilityDescription: nil)
        }

        required init(coder: NSCoder) { fatalError("not used") }

        @MainActor @objc private func choose() { model.setScenario(scenario) }
    }
}

/// Before the captions start, the three situations as tiles in the empty panel: the choice that shapes everything else.
struct SituationPicker: View {
    @ObservedObject var model: AppModel
    let palette: Theme.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("What are you doing?", "지금 무엇을 하시나요?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
            ForEach(Scenario.allCases, id: \.self) { scenario in
                tile(scenario)
            }
            Text(model.scenario.explanation)
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ scenario: Scenario) -> some View {
        let selected = scenario == model.scenario
        return Button(action: { model.setScenario(scenario) }) {
            HStack(spacing: 12) {
                Image(systemName: scenario.symbol)
                    .font(.system(size: 18))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.title).font(.system(size: 14, weight: .semibold))
                    Text(scenario.hint).font(.system(size: 12)).foregroundStyle(palette.interim)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.interim.opacity(selected ? 0.24 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.ink.opacity(selected ? 0.45 : 0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
