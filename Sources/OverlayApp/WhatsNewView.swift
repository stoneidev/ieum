import AppKit
import CaptionCore
import SwiftUI

// MARK: - Content

/// One highlight of the "What's new" tour.
struct WhatsNewPage: Identifiable {
    enum Art { case wordsLive, modes, tryIt, menu, onTop, updates }

    let id: String
    /// The first version that has it; a person who last saw an older version is shown this page.
    let introduced: String
    let art: Art
    let title: String
    let body: String
}

@MainActor
enum WhatsNewCatalog {
    /// Newest first: the page most worth seeing comes first.
    static func pages() -> [WhatsNewPage] { [
        WhatsNewPage(
            id: "updates", introduced: "0.3.0", art: .updates,
            title: tr("Updates, when you say so", "업데이트는 허락하면 알아서"),
            body: tr("Ieum now checks once a day whether a newer version exists and asks before installing it. The check sends no audio, text or identifiers, and you can turn it off in Settings.",
                     "Ieum이 하루에 한 번 새 버전이 있는지 확인하고, 설치하기 전에 먼저 물어봅니다. 확인에는 음성도, 글자도, 식별 정보도 보내지 않으며 설정에서 끌 수 있습니다.")
        ),
        WhatsNewPage(
            id: "on-top", introduced: "0.2.8", art: .onTop,
            title: tr("You decide where the captions sit", "자막이 놓일 자리를 직접 정하세요"),
            body: tr("Keep them above every window, or let them behave like any other window. If something covers them, ⌃⌥H brings them back. Find it in Settings → Display.",
                     "항상 맨 위에 둘 수도, 일반 창처럼 다른 창 뒤로 보낼 수도 있습니다. 무언가에 가려지면 ⌃⌥H로 앞으로 나옵니다. 설정 → 화면에 있습니다.")
        ),
        WhatsNewPage(
            id: "try-it", introduced: "0.2.7", art: .tryIt,
            title: tr("Try it before the meeting", "회의 전에 먼저 체험해 보세요"),
            body: tr("Open Permissions and setup and press Run test. Ieum plays a sentence and shows it coming back as captions and a Korean translation, so you know it works.",
                     "권한 및 설정 점검에서 테스트 실행을 누르면, 문장을 들려주고 자막과 한국어 번역으로 돌아오는 것을 보여 줍니다. 회의 전에 잘 되는지 바로 알 수 있습니다.")
        ),
        WhatsNewPage(
            id: "menu", introduced: "0.2.6", art: .menu,
            title: tr("The menu is never out of reach", "메뉴가 숨어도 걱정 없습니다"),
            body: tr("When macOS hides the menu bar icon because the bar is full, the ⋯ button on the captions opens the same menu.",
                     "메뉴 막대가 가득 차 macOS가 아이콘을 숨겨도, 자막에 있는 ⋯ 버튼에서 같은 메뉴를 열 수 있습니다.")
        ),
        WhatsNewPage(
            id: "modes", introduced: "0.2.4", art: .modes,
            title: tr("Five meeting modes, named plainly", "회의 모드는 이제 다섯 가지, 이름 그대로"),
            body: tr("Korean → English, English → Korean, Korean captions, English captions, or let Ieum detect the language and translate. Switch any time with ⌃⌥L or from the menu.",
                     "한국어 → 영어, 영어 → 한국어, 한국어 자막, 영어 자막, 그리고 언어를 알아서 알아내 번역하는 자동 모드. ⌃⌥L이나 메뉴에서 언제든 바꿀 수 있습니다.")
        ),
        WhatsNewPage(
            id: "words", introduced: "0.2.4", art: .wordsLive,
            title: tr("Words appear as they are spoken", "말하는 대로 바로 보입니다"),
            body: tr("The first words show up about half a second after someone starts speaking, then follow word by word. The translation arrives right behind.",
                     "말을 시작하고 약 0.5초 만에 첫 단어가 나타나고, 이후 단어마다 이어집니다. 번역은 바로 뒤따라 옵니다.")
        ),
    ] }

    /// The pages to show at launch, or none.
    static func pending(lastSeen: String?, current: String, isFirstInstall: Bool) -> [WhatsNewPage] {
        let all = pages()
        let indices = WhatsNew.pending(introduced: all.map(\.introduced), lastSeen: lastSeen, current: current, isFirstInstall: isFirstInstall)
        return indices.map { all[$0] }
    }
}

// MARK: - Window

/// The "What's new" window: dark, borderless-looking, one page per highlight.
@MainActor
final class WhatsNewWindow {
    private var window: NSWindow?

    func show(pages: [WhatsNewPage], version: String) {
        guard !pages.isEmpty else { return }
        window?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WhatsNewView.size.width, height: WhatsNewView.size.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = tr("What's new", "새로운 기능")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.078, green: 0.086, blue: 0.098, alpha: 1)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: WhatsNewView(pages: pages, version: version) { [weak self] in self?.window?.close() })
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // also when the app was started at login and is not the active one
    }
}

// MARK: - View

enum Style {
    static let ink = Color(red: 0.957, green: 0.949, blue: 0.933)
    static let muted = Color(red: 0.612, green: 0.639, blue: 0.671)
    static let tint = Color(red: 0.082, green: 0.094, blue: 0.106)
    static let amber = Theme.live
}

struct WhatsNewView: View {
    static let size = CGSize(width: 640, height: 580)

    let pages: [WhatsNewPage]
    let version: String
    let onDone: () -> Void

    @State private var index = 0
    @State private var forward = true
    @State private var appeared = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: WhatsNewPage { pages[index] }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                stage
                    .padding(.top, 18)
                text
                    .padding(.top, 26)
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .preferredColorScheme(.dark)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
        .onAppear {
            focused = true
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { appeared = true }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.return) { advance(); return .handled }
        .onKeyPress(.escape) { onDone(); return .handled }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.086, green: 0.094, blue: 0.108), Color(red: 0.063, green: 0.067, blue: 0.078)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Style.amber.opacity(0.16), .clear], center: .init(x: 0.82, y: 0.0), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Color(red: 0.4, green: 0.5, blue: 0.7).opacity(0.10), .clear], center: .init(x: 0.0, y: 0.35), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("What's new in Ieum", "Ieum의 새로운 기능"))
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Style.ink)
                Text(tr("\(pages.count) things worth knowing", "알아두면 좋은 \(pages.count)가지"))
                    .font(.system(size: 12))
                    .foregroundStyle(Style.muted)
            }
            Spacer()
            Text(version)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Style.amber))
        }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            WhatsNewArt(kind: page.art, still: reduceMotion)
                .id(page.id)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(page.title)
                .font(.system(size: 27, weight: .semibold, design: .serif))
                .foregroundStyle(Style.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.body)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .id("text-\(page.id)")
        .transition(.opacity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if isLast {
                Color.clear.frame(width: 56, height: 1)
            } else {
                Button(tr("Skip", "건너뛰기"), action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.muted)
                    .frame(width: 56, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? Style.amber : Color.white.opacity(0.22))
                        .frame(width: dot == index ? 22 : 7, height: 7)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: index)
                        .onTapGesture { go(to: dot) }
                }
            }
            .accessibilityHidden(true)
            Spacer()
            HStack(spacing: 10) {
                if index > 0 {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Style.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Back", "이전"))
                }
                Button(action: advance) {
                    Text(isLast ? tr("Start using Ieum", "Ieum 시작하기") : tr("Next", "다음"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .padding(.horizontal, 20)
                        .frame(height: 34)
                        .background(Capsule().fill(Style.amber))
                        .shadow(color: Style.amber.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
    }

    // MARK: Navigation

    private func advance() {
        if isLast { onDone() } else { go(to: index + 1) }
    }

    private func back() { go(to: index - 1) }

    private func go(to target: Int) {
        guard target != index, pages.indices.contains(target) else { return }
        forward = target > index
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) { index = target }
    }
}

// MARK: - Illustrations

/// Small looping scenes, one per highlight, drawn with the same colors as the app.
private struct WhatsNewArt: View {
    let kind: WhatsNewPage.Art
    let still: Bool

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let t = still ? Self.stillTime(kind) : context.date.timeIntervalSinceReferenceDate
            switch kind {
            case .wordsLive: WordsScene(t: t)
            case .modes: ModesScene(t: t)
            case .tryIt: TryItScene(t: t)
            case .menu: MenuScene(t: t)
            case .onTop: OnTopScene(t: t)
            case .updates: UpdatesScene(t: t)
            }
        }
    }

    /// With reduced motion the scene stands still at its most telling moment.
    private static func stillTime(_ kind: WhatsNewPage.Art) -> Double {
        switch kind {
        case .wordsLive: 5
        case .modes: 0
        case .tryIt: 5.2
        case .menu: 3
        case .onTop: 1
        case .updates: 3.2
        }
    }
}

private func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
    guard end > start else { return value >= end ? 1 : 0 }
    return min(1, max(0, (value - start) / (end - start)))
}

private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

/// A caption bar like the real one: dark glass, a tally light, small original above, large translation below.
private struct BarMock<Content: View>: View {
    var width: CGFloat = 440
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7, content: content)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Style.tint.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

private struct TallyDot: View {
    let t: Double
    var body: some View {
        Circle()
            .fill(Style.amber)
            .frame(width: 8, height: 8)
            .opacity(0.55 + 0.45 * (0.5 + 0.5 * sin(t * 4)))
    }
}

private struct WordsScene: View {
    let t: Double
    private let english = "Could you share the schedule for next week?".split(separator: " ").map(String.init)

    var body: some View {
        let cycle = 8.0
        let time = t.truncatingRemainder(dividingBy: cycle)
        let shown = min(english.count, max(0, Int((time - 0.5) / 0.3) + 1))
        let confirmed = ramp(time, from: 3.3, to: 3.7)
        let korean = easeOut(ramp(time, from: 3.5, to: 4.2))
        let fade = 1 - ramp(time, from: 7.2, to: 8.0)
        BarMock(width: 470) {
            HStack(spacing: 10) {
                TallyDot(t: t)
                Text(english.prefix(shown).joined(separator: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.muted.mix(with: Style.ink, by: confirmed))
                Spacer(minLength: 0)
            }
            Text("다음 주 일정을 공유해 주시겠습니까?")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Style.ink)
                .opacity(korean)
                .offset(y: (1 - korean) * 8)
                .padding(.leading, 18)
        }
        .opacity(fade)
        .overlay(alignment: .topTrailing) {
            Text(tr("first words ≈ 0.5 s", "첫 단어 약 0.5초"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Style.amber)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Style.amber.opacity(0.14)))
                .opacity(ramp(time, from: 0.6, to: 1.2) * fade)
                .offset(x: 12, y: -24)
        }
    }
}

private extension Color {
    /// A simple blend, enough for text that turns from muted to bright.
    func mix(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .white
        let k = CGFloat(min(1, max(0, amount)))
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * k,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k)
    }
}

private struct ModesScene: View {
    let t: Double

    private var names: [String] { [
        tr("Korean → English", "한국어 → 영어"),
        tr("English → Korean", "영어 → 한국어"),
        tr("Korean captions", "한국어 자막"),
        tr("English captions", "영어 자막"),
        tr("Detect & translate", "언어 자동 인식 번역"),
    ] }

    var body: some View {
        let active = Int(t / 1.3) % 5
        VStack(spacing: 12) {
            HStack(spacing: 10) { chip(0, active); chip(1, active); chip(2, active) }
            HStack(spacing: 10) { chip(3, active); chip(4, active) }
        }
    }

    private func chip(_ index: Int, _ active: Int) -> some View {
        let on = index == active
        return Text(names[index])
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(on ? Color.black.opacity(0.88) : Style.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(on ? Style.amber : Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(on ? Style.amber : Color.white.opacity(0.14), lineWidth: 1))
            .scaleEffect(on ? 1.06 : 1)
            .shadow(color: on ? Style.amber.opacity(0.4) : .clear, radius: 12)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: on)
    }
}

private struct TryItScene: View {
    let t: Double

    var body: some View {
        let time = t.truncatingRemainder(dividingBy: 7.0)
        let waves = ramp(time, from: 0.2, to: 0.6) * (1 - ramp(time, from: 2.6, to: 3.0))
        let travel = ramp(time, from: 1.2, to: 3.4)
        let english = easeOut(ramp(time, from: 3.4, to: 4.0))
        let korean = easeOut(ramp(time, from: 4.4, to: 5.0))
        let check = easeOut(ramp(time, from: 5.2, to: 5.7))
        let fade = 1 - ramp(time, from: 6.4, to: 7.0)
        HStack(spacing: 20) {
            ZStack {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Style.ink)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: waves > 0)
            }
            .frame(width: 54)
            .opacity(0.5 + 0.5 * waves)
            travelDots(progress: travel)
            Image(systemName: "mic.fill")
                .font(.system(size: 30))
                .foregroundStyle(Style.ink)
                .frame(width: 40)
                .opacity(0.5 + 0.5 * ramp(time, from: 2.4, to: 3.2))
            travelDots(progress: ramp(time, from: 3.0, to: 3.8))
            VStack(alignment: .leading, spacing: 6) {
                Text("Hello. This is a test.")
                    .font(.system(size: 12))
                    .foregroundStyle(Style.muted)
                    .opacity(english)
                Text("안녕하세요. 이것은 테스트입니다.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.ink)
                    .opacity(korean)
            }
            .frame(width: 170, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Style.tint.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(red: 0.36, green: 0.82, blue: 0.45), Color.black.opacity(0.2))
                    .background(Circle().fill(Style.tint).padding(3))
                    .scaleEffect(0.4 + 0.6 * check)
                    .opacity(check)
                    .offset(x: 10, y: -12)
            }
        }
        .opacity(fade)
    }

    private func travelDots(progress: Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { dot in
                let lit = progress > 0 && progress < 1 && abs(progress * 4.5 - Double(dot) - 0.5) < 1.0
                Circle()
                    .fill(lit ? Style.amber : Color.white.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

private struct MenuScene: View {
    let t: Double

    var body: some View {
        let time = t.truncatingRemainder(dividingBy: 6.0)
        let press = ramp(time, from: 1.6, to: 2.0) * (1 - ramp(time, from: 5.2, to: 5.7))
        VStack(spacing: 18) {
            // A crowded menu bar: Ieum's icon is the one that does not fit.
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { slot in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 18, height: 12)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Style.amber.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 18, height: 12)
                    .overlay(Image(systemName: "eye.slash").font(.system(size: 8)).foregroundStyle(Style.amber.opacity(0.8)))
                Spacer(minLength: 0)
                Text("9:41").font(.system(size: 11, weight: .medium)).foregroundStyle(Style.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))

            ZStack(alignment: .topTrailing) {
                BarMock(width: 400) {
                    HStack(spacing: 10) {
                        Circle().fill(Style.muted.opacity(0.6)).frame(width: 8, height: 8)
                        Text(tr("Captions are off", "자막이 꺼져 있습니다"))
                            .font(.system(size: 13))
                            .foregroundStyle(Style.muted)
                        Spacer(minLength: 0)
                        Capsule().fill(Style.amber).frame(width: 64, height: 20)
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(press > 0.3 ? Style.amber : Style.muted)
                            .scaleEffect(1 + 0.25 * sin(press * .pi))
                    }
                }
                menuCard.opacity(press).offset(x: -4, y: 52).scaleEffect(0.92 + 0.08 * press, anchor: .topTrailing)
            }
        }
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([tr("Start captions", "자막 시작"), tr("Meeting mode", "회의 모드"), tr("Settings…", "설정…")], id: \.self) { item in
                Text(item)
                    .font(.system(size: 12))
                    .foregroundStyle(Style.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
        }
        .frame(width: 140, alignment: .leading)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.16, green: 0.17, blue: 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }
}

private struct OnTopScene: View {
    let t: Double

    var body: some View {
        let time = t.truncatingRemainder(dividingBy: 8.0)
        // 0-2.8 the captions are on top; 2.8-5.2 a window covers them; 5.2-8 the shortcut brings them back.
        let covered = time >= 2.8 && time < 5.2
        let keys = ramp(time, from: 4.4, to: 4.8) * (1 - ramp(time, from: 7.4, to: 7.9))
        let bump = covered ? 0 : 1 - easeOut(ramp(time < 2.8 ? time : time - 5.2, from: 0, to: 0.5))
        ZStack {
            if covered {
                barWindow(pinned: false).offset(y: 56)
                callWindow.offset(x: -40, y: -8)
            } else {
                callWindow.offset(x: -40, y: -8)
                barWindow(pinned: time < 2.8).offset(y: 56 - bump * 6)
            }
            HStack(spacing: 4) {
                ForEach(["⌃", "⌥", "H"], id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Style.ink)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.14)))
                }
            }
            .opacity(keys)
            .offset(x: 170, y: -64)
        }
    }

    private var callWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.25)).frame(width: 7, height: 7) }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color.white.opacity(0.08))
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { tile in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(tile == 1 ? 0.16 : 0.09))
                        .overlay(Image(systemName: "person.fill").font(.system(size: 22)).foregroundStyle(Color.white.opacity(0.2)))
                }
            }
            .padding(10)
        }
        .frame(width: 330, height: 150)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.2, green: 0.22, blue: 0.27)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }

    private func barWindow(pinned: Bool) -> some View {
        BarMock(width: 300) {
            HStack(spacing: 8) {
                Circle().fill(Style.amber).frame(width: 7, height: 7)
                Text("다음 주 일정을 공유해 주시겠습니까?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: pinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(pinned ? Style.amber : Style.muted)
            }
        }
    }
}

private struct UpdatesScene: View {
    let t: Double

    var body: some View {
        let time = t.truncatingRemainder(dividingBy: 8.0)
        let press = easeOut(ramp(time, from: 2.2, to: 2.5))
        let progress = ramp(time, from: 2.6, to: 5.4)
        let restart = ramp(time, from: 5.6, to: 6.0)
        let fade = 1 - ramp(time, from: 7.4, to: 8.0)
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(restart > 0.5 ? tr("Restarting Ieum…", "Ieum을 다시 시작합니다…") : tr("Ieum 0.3.1 is available", "Ieum 0.3.1 업데이트가 있습니다"))
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(Style.ink)
                        Text(progress > 0 && restart < 0.5 ? tr("Downloading… \(Int(progress * 100)) %", "내려받는 중… \(Int(progress * 100)) %") : tr("You have 0.3.0", "현재 버전 0.3.0"))
                            .font(.system(size: 12))
                            .foregroundStyle(Style.muted)
                            .monospacedDigit()
                    }
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Style.amber).frame(width: 300 * progress)
                }
                .frame(width: 300, height: 5)
                .opacity(progress > 0 ? 1 : 0)
                HStack(spacing: 10) {
                    Spacer()
                    Text(tr("Later", "나중에"))
                        .font(.system(size: 12))
                        .foregroundStyle(Style.ink)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                    Text(tr("Update now", "지금 업데이트"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(Style.amber))
                        .scaleEffect(1 - 0.08 * sin(press * .pi))
                        .shadow(color: Style.amber.opacity(0.4 * (1 - press)), radius: 10)
                }
                .opacity(progress > 0 ? 0.3 : 1)
            }
            .padding(18)
            .frame(width: 350)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Style.tint.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .opacity(fade)
    }
}
