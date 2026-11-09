import AppKit
import Combine
import SwiftUI

/// Floating, non-activating panel. Only the transcript panel mode may take key focus (for text selection).
final class OverlayPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay window: placement per display mode, persistence of position and size.
@MainActor
final class OverlayWindowController {
    private let model: AppModel
    private let panel: OverlayPanel
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var applyingFrame = false

    init(model: AppModel) {
        self.model = model
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 120),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = model.keepsOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Captions"

        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting

        applyMode(model.displayMode)

        model.$displayMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in self?.applyMode(mode) }
            .store(in: &cancellables)

        // `@Published` emits before the value changes, so use the emitted values. Resizing the window redraws the
        // SwiftUI content immediately; doing that inside the emission would draw it with the old values and then
        // never redraw, so the work is deferred to the next main-queue turn.
        Publishers.CombineLatest4(model.$barLines, model.$textSize, model.$showsSecondaryRow, model.$status.map { $0 == .idle }.removeDuplicates())
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines, size, secondary, idle in self?.fitBarHeight(lines: lines, size: size.points, secondaryRow: secondary, idle: idle) }
            .store(in: &cancellables)
        model.$status
            .map { $0 == .idle }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPresence() }
            .store(in: &cancellables)

        // Hidden and click-through are state of the model; the window just follows.
        model.$keepsOnTop
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPresence() }
            .store(in: &cancellables)
        model.$overlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPresence() }
            .store(in: &cancellables)
        model.$clickThrough
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPresence() }
            .store(in: &cancellables)
        applyPresence()

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })
        }
    }

    func show() { applyPresence() }

    /// Visible or hidden; and whether clicks pass through to the window underneath.
    private func applyPresence() {
        // The Start button on the idle bar must stay clickable, even with click-through on.
        panel.ignoresMouseEvents = model.clickThrough && model.status != .idle
        guard model.overlayVisible else {
            panel.orderOut(nil)
            return
        }
        panel.level = model.keepsOnTop ? .floating : .normal
        // On top, the captions are always raised. As an ordinary window they are only raised when they were not showing,
        // so a status change never pulls them over what the person is working in.
        if model.keepsOnTop || !panel.isVisible { panel.orderFrontRegardless() }
        panel.alphaValue = 1
    }

    func bringToFront() { panel.orderFrontRegardless() }

    /// Whether another app's window sits above the captions and overlaps them (only meaningful when they are not kept on top).
    func isCoveredByAnotherWindow() -> Bool {
        guard panel.isVisible,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first
        else { return false }
        // Window bounds are top-left based; AppKit frames are bottom-left based on the primary screen.
        let frame = panel.frame
        let mine = CGRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {   // front to back
            if (window[kCGWindowNumber as String] as? Int) == panel.windowNumber { return false }
            guard (window[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            if CGRect(x: x, y: y, width: width, height: height).intersects(mine) { return true }
        }
        return false
    }

    // MARK: Placement

    private func applyMode(_ mode: DisplayMode) {
        applyingFrame = true
        defer { applyingFrame = false }
        panel.allowsKey = mode == .panel
        var frame = savedFrame(for: mode) ?? defaultFrame(for: mode)
        switch mode {
        case .bar:
            // The bar is exactly as tall as its lines; only its width and position are the user's to change.
            let height = barHeight(lines: model.barLines, size: model.textSize.points, secondaryRow: model.showsSecondaryRow, idle: model.status == .idle)
            panel.minSize = NSSize(width: 420, height: height)
            panel.maxSize = NSSize(width: 4000, height: height)
            frame.size.height = height
        case .panel:
            panel.minSize = NSSize(width: 320, height: 240)
            panel.maxSize = NSSize(width: 1400, height: 2000)
        }
        panel.setFrame(frame, display: true, animate: false)
        if model.overlayVisible { panel.orderFrontRegardless() }
    }

    private func barHeight(lines: Int, size: CGFloat, secondaryRow: Bool, idle: Bool) -> CGFloat {
        idle ? BarMetrics.idleHeight(size: size) : BarMetrics.height(lines: lines, size: size, secondaryRow: secondaryRow)
    }

    /// Re-fits the bar after the line count or text size changed. It grows upward from its bottom edge.
    private func fitBarHeight(lines: Int, size: CGFloat, secondaryRow: Bool, idle: Bool) {
        guard model.displayMode == .bar else { return }
        let height = barHeight(lines: lines, size: size, secondaryRow: secondaryRow, idle: idle)
        panel.minSize = NSSize(width: 420, height: height)
        panel.maxSize = NSSize(width: 4000, height: height)
        var frame = panel.frame
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func defaultFrame(for mode: DisplayMode) -> NSRect {
        let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        switch mode {
        case .bar:
            let width = min(area.width * 0.62, 1100)
            return NSRect(x: area.midX - width / 2, y: area.minY + 56, width: width, height: BarMetrics.height(lines: model.barLines, size: model.textSize.points, secondaryRow: model.showsSecondaryRow))
        case .panel:
            let size = NSSize(width: 440, height: min(600, area.height * 0.7))
            return NSRect(x: area.maxX - size.width - 24, y: area.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private func key(for mode: DisplayMode) -> String { "overlayFrame.\(mode.rawValue)" }

    private func saveFrame() {
        guard !applyingFrame else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: key(for: model.displayMode))
    }

    /// A saved frame is only used when it is still reachable on a connected screen.
    private func savedFrame(for mode: DisplayMode) -> NSRect? {
        guard let text = UserDefaults.standard.string(forKey: key(for: mode)) else { return nil }
        let frame = NSRectFromString(text)
        guard frame.width >= 100, frame.height >= 60 else { return nil }
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersection(frame).width >= 80 && $0.visibleFrame.intersection(frame).height >= 40 }
        return visible ? frame : nil
    }
}
