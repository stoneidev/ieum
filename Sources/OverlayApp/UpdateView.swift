import AppKit
import CaptionCore
import SwiftUI

/// The update window: the same dark look as the What's new tour, one calm screen per state.
@MainActor
final class UpdateWindow {
    private var window: NSWindow?
    private let updater: Updater

    init(updater: Updater) { self.updater = updater }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: UpdateView.size.width, height: UpdateView.size.height),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = tr("Ieum update", "Ieum 업데이트")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(red: 0.078, green: 0.086, blue: 0.098, alpha: 1)
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentView = NSHostingView(rootView: UpdateView(updater: updater) { [weak window] in window?.close() })
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct UpdateView: View {
    static let size = CGSize(width: 520, height: 400)

    @ObservedObject var updater: Updater
    let close: () -> Void

    private var current: String {
        Preferences.updateCurrentVersionOverride ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.086, green: 0.094, blue: 0.108), Color(red: 0.063, green: 0.067, blue: 0.078)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Style.amber.opacity(0.14), .clear], center: .init(x: 0.85, y: 0), startRadius: 0, endRadius: 320)
            content
                .padding(.horizontal, 34)
                .padding(.top, 38)
                .padding(.bottom, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: updater.state)
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            message(icon: nil, title: tr("Checking for updates…", "업데이트를 확인하는 중…"), detail: nil, spinner: true)
        case .upToDate:
            message(icon: ("checkmark.circle.fill", .green), title: tr("Ieum is up to date", "최신 버전입니다"),
                    detail: tr("You have version \(current), the newest one.", "현재 버전 \(current)은 가장 최신입니다."), buttons: [done])
        case .needsNewerMacOS(let required):
            message(icon: ("info.circle.fill", Style.amber), title: tr("A newer Ieum is out", "더 새로운 Ieum이 나왔습니다"),
                    detail: tr("It needs macOS \(required) or later, so this Mac keeps version \(current).", "macOS \(required) 이상이 필요해서 이 Mac은 버전 \(current)을 계속 씁니다."), buttons: [done])
        case .available(let feed):
            offer(feed)
        case .downloading(let progress):
            progressView(title: tr("Downloading the update…", "업데이트를 내려받는 중…"), value: progress)
        case .verifying:
            message(icon: nil, title: tr("Checking the update…", "업데이트를 확인하는 중…"),
                    detail: tr("Making sure it is exactly what was published, signed by the developer and approved by Apple.", "공개된 파일과 같은지, 개발자 서명과 애플 공증이 맞는지 확인합니다."), spinner: true)
        case .installing:
            message(icon: nil, title: tr("Restarting Ieum…", "Ieum을 다시 시작합니다…"),
                    detail: tr("The new version opens in a moment.", "잠시 후 새 버전이 열립니다."), spinner: true)
        case .manualInstall(let url):
            message(icon: ("shippingbox.fill", Style.amber), title: tr("The update is ready", "업데이트가 준비됐습니다"),
                    detail: tr("This copy of Ieum cannot be replaced from inside. The checked new version is in Downloads: quit Ieum, then drag it into Applications.",
                               "이 Ieum은 앱 안에서 바꿀 수 없는 위치에 있습니다. 확인을 마친 새 버전이 다운로드 폴더에 있습니다. Ieum을 종료한 뒤 응용 프로그램 폴더로 끌어다 놓으세요."),
                    buttons: [AnyView(primary(tr("Show in Finder", "Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }), done])
        case .failed(let reason):
            message(icon: ("exclamationmark.triangle.fill", .orange), title: tr("The update did not work", "업데이트하지 못했습니다"), detail: reason,
                    buttons: [AnyView(secondary(tr("Open the download page", "다운로드 페이지 열기")) { NSWorkspace.shared.open(Updater.releasePage) }), done])
        }
    }

    // MARK: Screens

    private func offer(_ feed: UpdateFeed) -> some View {
        let notes = UpdateCheck.notes(of: feed, language: L10n.isKorean ? "ko" : "en")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Ieum \(feed.version) is available", "Ieum \(feed.version) 업데이트가 있습니다"))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Style.ink)
                    Text(tr("You have \(current).", "현재 버전 \(current)") + (feed.size.map { "  ·  " + sizeText($0) } ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(Style.muted)
                }
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(notes.prefix(5).enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Style.amber).frame(width: 5, height: 5).offset(y: -2)
                            Text(note).font(.system(size: 14)).foregroundStyle(Style.ink.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 22)
            }
            Spacer(minLength: 12)
            Text(tr("Installing replaces this app and reopens it. Your settings and transcripts are kept.",
                    "설치하면 이 앱이 새 버전으로 바뀌고 다시 열립니다. 설정과 기록은 그대로 남습니다."))
                .font(.system(size: 12))
                .foregroundStyle(Style.muted)
                .padding(.bottom, 14)
            HStack(spacing: 12) {
                Button(tr("Skip this version", "이 버전 건너뛰기")) { updater.skip(feed); close() }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Style.muted)
                Spacer()
                Button(tr("Later", "나중에")) { updater.dismiss(); close() }
                    .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Style.ink)
                    .padding(.horizontal, 16).frame(height: 34).background(Capsule().fill(Color.white.opacity(0.09)))
                primary(tr("Update now", "지금 업데이트")) { updater.install(feed) }
            }
        }
    }

    private func progressView(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(title).font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Style.ink)
            ProgressView(value: value).tint(Style.amber)
            Text("\(Int(value * 100)) %").font(.system(size: 13, design: .rounded)).foregroundStyle(Style.muted).monospacedDigit()
            Spacer()
        }
    }

    private func message(icon: (String, Color)?, title: String, detail: String?, spinner: Bool = false, buttons: [AnyView] = []) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if spinner { ProgressView().controlSize(.large) }
            if let icon { Image(systemName: icon.0).font(.system(size: 40)).foregroundStyle(icon.1) }
            Text(title).font(.system(size: 21, weight: .semibold, design: .serif)).foregroundStyle(Style.ink).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 14)).foregroundStyle(Style.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !buttons.isEmpty {
                HStack(spacing: 12) { ForEach(buttons.indices, id: \.self) { buttons[$0] } }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var done: AnyView { AnyView(secondary(tr("Close", "닫기")) { updater.dismiss(); close() }) }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black.opacity(0.88))
                .padding(.horizontal, 20).frame(height: 34)
                .background(Capsule().fill(Style.amber))
                .shadow(color: Style.amber.opacity(0.35), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14)).foregroundStyle(Style.ink)
                .padding(.horizontal, 18).frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    private func sizeText(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_000_000) }
}
