import AppKit
import CaptionCore
import Combine
import SwiftUI

/// A small floating panel that takes typing without taking Ieum (or the meeting window behind it) to the front.
private final class ReplyNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Opens beside the subtitle bar when the reply shortcut is pressed. Typing goes straight into it; Esc closes it.
@MainActor
final class ReplyPanelController {
    private let model: ReplyModel
    private let panel: ReplyNSPanel
    private var cancellables: Set<AnyCancellable> = []
    private static let width: CGFloat = 580

    init(app: AppModel) {
        model = ReplyModel(app: app)
        panel = ReplyNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Reply"
        panel.isMovableByWindowBackground = true
        ScreenShare.protect(panel)

        let hosting = NSHostingView(rootView: ReplyView(model: model, close: { [weak self] in self?.hide() }))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting

        // The card grows and shrinks with its content; it keeps its place beside the bar.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fit() }
            .store(in: &cancellables)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(near overlay: NSRect?) {
        isVisible ? hide() : show(near: overlay)
    }

    func show(near overlay: NSRect?) {
        ScreenShare.protect(panel)
        model.opened()
        anchor = overlay
        fit()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        model.closed()
        panel.orderOut(nil)
    }

    private var anchor: NSRect?

    /// Above the bar when there is room, below it otherwise (a bar that stepped to the top edge). Always inside the screen the bar is on.
    private func fit() {
        guard let hosting = panel.contentView else { return }
        let size = NSSize(width: Self.width, height: max(120, hosting.fittingSize.height))
        let screen = (anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        var frame: NSRect
        if panel.isVisible, !panel.frame.isEmpty {
            // Once on screen the card stays where it is (or where the person dragged it); only its height changes, from the edge
            // that faces the bar, so the part nearest the bar does not move.
            let above = anchor.map { panel.frame.minY >= $0.maxY - 1 } ?? true
            let y = above ? panel.frame.minY : panel.frame.maxY - size.height
            frame = NSRect(x: panel.frame.minX, y: y, width: size.width, height: size.height)
        } else if let anchor {
            frame = NSRect(x: anchor.midX - size.width / 2, y: anchor.maxY + 10, width: size.width, height: size.height)
            if frame.maxY > screen.maxY { frame.origin.y = anchor.minY - size.height - 10 }
        } else {
            frame = NSRect(x: screen.midX - size.width / 2, y: screen.minY + 160, width: size.width, height: size.height)
        }
        frame.origin.x = min(max(frame.origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        frame.origin.y = min(max(frame.origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(frame, display: true)
    }
}

struct ReplyView: View {
    @ObservedObject var model: ReplyModel
    let close: () -> Void
    @ObservedObject private var app: AppModel
    @FocusState private var focused: Bool

    init(model: ReplyModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _app = ObservedObject(wrappedValue: model.app)
    }

    private var palette: Theme.Palette { Theme.palette(for: app.background) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let pair = model.pair {
                field(pair)
                result(pair)
                historyList
            } else {
                Text(tr("Choose the language you read first (menu > Language you read), so Ieum knows what to translate your reply from.",
                        "먼저 '보는 언어'를 고르세요(메뉴 > 보는 언어). 어떤 언어에서 답장을 번역할지 알아야 합니다."))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.interim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 580, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.tint.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .preferredColorScheme(palette.scheme)
        .onChange(of: model.focusToken, initial: true) { _, _ in focused = true }
        .onExitCommand(perform: close)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            Text(tr("Reply helper", "답장 도우미"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            if let pair = model.pair {
                Button(action: { model.toggleDirection() }) {
                    HStack(spacing: 5) {
                        Text("\(pair.from.nativeName) → \(pair.to.nativeName)")
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 10))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.interim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.interim.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help(tr("Swap the direction", "방향 바꾸기"))
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.interim)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(tr("Close", "닫기"))
        }
    }

    private func field(_ pair: (from: SpokenLanguage, to: SpokenLanguage)) -> some View {
        HStack(spacing: 8) {
            TextField(tr("What do you want to say? (\(pair.from.nativeName))", "하고 싶은 말을 쓰세요 (\(pair.from.nativeName))"), text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(palette.ink)
                .focused($focused)
                .onSubmit { model.submit() }
            Button(action: { model.toggleListening() }) {
                Image(systemName: model.listening ? "waveform.circle.fill" : "mic")
                    .font(.system(size: 15))
                    .foregroundStyle(model.listening ? Theme.live : palette.interim)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.listening ? tr("Listening… click to stop", "듣는 중… 누르면 멈춥니다") : tr("Say it quietly instead of typing", "입력 대신 조용히 말하기"))
            .accessibilityLabel(tr("Dictate", "음성 입력"))
            Button(action: { model.submit() }) {
                Text(tr("Translate", "번역") + " ⏎")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(palette.interim.opacity(0.28)))
            }
            .buttonStyle(.plain)
            .disabled(ReplyHelper.prepare(model.input) == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.interim.opacity(0.14)))
    }

    @ViewBuilder
    private func result(_ pair: (from: SpokenLanguage, to: SpokenLanguage)) -> some View {
        switch model.phase {
        case .idle:
            Text(tr("Type or say it in your language, then press Return. A sentence you can read out appears here.",
                    "내 언어로 쓰거나 말하고 Return을 누르세요. 그대로 읽을 수 있는 문장이 여기에 나옵니다."))
                .font(.system(size: 12))
                .foregroundStyle(palette.interim)
        case .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("Translating…", "번역하는 중…")).font(.system(size: 13)).foregroundStyle(palette.interim)
            }
        case .failed(let message):
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.alert).fixedSize(horizontal: false, vertical: true)
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                Text(model.reply)
                    .font(.system(size: ScriptScale.factor(for: model.reply) * 24, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(action: { model.copy() }) {
                        Text(model.copied ? "✓ " + tr("Copied", "복사됨") : tr("Copy", "복사"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(palette.interim.opacity(model.copied ? 0.40 : 0.28)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    if model.polishing {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text(tr("Making it sound natural…", "자연스럽게 다듬는 중…")).font(.system(size: 11)).foregroundStyle(palette.interim)
                        }
                    } else if model.polished != nil {
                        Text(tr("Smoothed on this Mac", "이 Mac에서 다듬음")).font(.system(size: 11)).foregroundStyle(palette.interim)
                    }
                    Spacer()
                    Button(action: { model.clear(); focused = true }) {
                        Text(tr("New", "새로 쓰기")).font(.system(size: 12)).foregroundStyle(palette.interim)
                    }
                    .buttonStyle(.plain)
                }
                if let polished = model.polished, polished != model.literal {
                    Button(action: { model.copy(model.literal) }) {
                        Text(tr("Literal: ", "직역: ") + model.literal)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.interim)
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Copy the literal translation instead", "직역을 대신 복사"))
                }
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        let older = Array(model.history.items.filter { $0.reply != model.reply }.prefix(3))
        if !older.isEmpty {
            Divider().overlay(palette.ink.opacity(0.10))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(older) { item in
                    Button(action: { model.copy(item.reply) }) {
                        HStack(spacing: 8) {
                            Text(item.reply).lineLimit(1).truncationMode(.tail).foregroundStyle(palette.ink.opacity(0.85))
                            Spacer(minLength: 6)
                            Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(palette.interim)
                        }
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.source)
                }
            }
        }
    }
}
