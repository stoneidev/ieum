import AppKit
import CaptionCore
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

    // Pointer avoidance (see `PointerAvoidance`): the bar steps aside when the pointer comes near.
    private var proximityTimer: Timer?
    private let zone = PointerZone()
    private var pointerNear = false
    /// See-through and letting clicks pass, because the pointer is over the words.
    private var faded = false
    private var lastNear = Date.distantPast
    /// Moved to the opposite edge; `homeFrame` is where it goes back to.
    private var dodged = false
    private var homeFrame: NSRect?
    private var lastDodge = Date.distantPast
    private var dodging = false
    /// A frame the app itself set (not the person dragging), so the move notification for it is not mistaken for a drag.
    private var programmaticFrame: NSRect?
    private static let fadedAlpha: CGFloat = 0.18

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
            .receive(on: DispatchQueue.main)
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
        // Hidden from screen sharing and recording unless the person turns that off.
        model.$hidesFromSharing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySharing() }
            .store(in: &cancellables)
        applySharing()
        proximityTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchPointer() }
        }
        RunLoop.main.add(proximityTimer!, forMode: .common)
        model.$pointerAvoidance
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.releaseAvoidance() }
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
        panel.ignoresMouseEvents = (model.clickThrough && model.status != .idle) || faded
        guard model.overlayVisible else {
            panel.orderOut(nil)
            return
        }
        panel.level = model.keepsOnTop ? .floating : .normal
        // On top, the captions are always raised. As an ordinary window they are only raised when they were not showing,
        // so a status change never pulls them over what the person is working in.
        if model.keepsOnTop || !panel.isVisible { panel.orderFrontRegardless() }
        panel.alphaValue = faded ? Self.fadedAlpha : 1
    }

    /// `.none` keeps the window out of what ScreenCaptureKit (Zoom, Meet, Teams, QuickTime) captures. Checked on macOS 26.
    private func applySharing() {
        panel.sharingType = model.hidesFromSharing ? .none : .readOnly
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

    // MARK: Pointer avoidance

    private var avoidanceApplies: Bool {
        model.overlayVisible && model.displayMode == .bar && model.isRunning && !model.clickThrough && model.pointerAvoidance != .off
    }

    private func watchPointer() {
        guard avoidanceApplies else {
            if faded || dodged { releaseAvoidance() }
            pointerNear = false
            return
        }
        // While a menu is open or a mouse button is down (the person is dragging the bar, or using it), leave everything as it is.
        if RunLoop.main.currentMode == .eventTracking { return }
        if !faded, NSEvent.pressedMouseButtons != 0 { return }
        let near = zone.isNear(pointer: NSEvent.mouseLocation, bar: panel.frame, wasNear: pointerNear)
        if near { lastNear = Date() }
        pointerNear = near
        switch model.pointerAvoidance {
        case .fade:
            if near, !faded {
                faded = true
                panel.ignoresMouseEvents = true
                animateAlpha(Self.fadedAlpha)
            } else if !near, faded, Date().timeIntervalSince(lastNear) > 0.35 {
                unfade()
            }
        case .dodge:
            if near, Date().timeIntervalSince(lastDodge) > 0.8 { dodge() }
        case .off:
            break
        }
    }

    private func animateAlpha(_ value: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = value
        }
    }

    private func unfade() {
        faded = false
        panel.ignoresMouseEvents = model.clickThrough && model.status != .idle
        animateAlpha(1)
    }

    /// To the opposite edge of the screen, or back where it came from.
    private func dodge() {
        lastDodge = Date()
        let target: NSRect
        if dodged, homeFrame != nil {
            releaseAvoidance()
            return
        } else {
            guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
            homeFrame = panel.frame
            target = PointerZone.opposite(of: panel.frame, in: visible)
            dodged = true
        }
        move(to: target)
    }

    private func move(to frame: NSRect) {
        dodging = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.dodging = false }
        })
    }

    /// Captions stopped, the bar became a panel, or the setting was turned off: everything goes back to normal.
    private func releaseAvoidance() {
        if faded { unfade() }
        if dodged, let home = homeFrame {
            dodged = false
            homeFrame = nil
            // Not a bar any more (it became the panel): nothing to go back to, and the panel places itself.
            guard model.displayMode == .bar else { return }
            // The screen it came from may be gone: then it goes where a new bar would.
            let onAScreen = NSScreen.screens.contains { !$0.visibleFrame.intersection(home).isNull && $0.visibleFrame.intersection(home).width >= 80 }
            move(to: onAScreen ? home : defaultFrame(for: .bar))
        }
    }

    // MARK: Placement

    private func applyMode(_ mode: DisplayMode) {
        // The bar's sidestep belongs to the bar: leaving it forgets it, and the window is solid again.
        faded = false
        dodged = false
        homeFrame = nil
        panel.alphaValue = 1
        panel.ignoresMouseEvents = model.clickThrough && model.status != .idle
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
        let oldHeight = frame.height
        frame.size.height = height
        // A bar dodged to the top edge grows downward, so it stays on the screen.
        if dodged, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, frame.midY > visible.midY { frame.origin.y -= height - oldHeight }
        homeFrame?.size.height = height
        if dodged { programmaticFrame = frame }
        panel.setFrame(frame, display: true, animate: false)
    }

    private func defaultFrame(for mode: DisplayMode) -> NSRect {
        let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        switch mode {
        case .bar:
            let width = min(area.width * 0.62, 1100)
            return NSRect(x: area.midX - width / 2, y: area.minY + 56, width: width, height: BarMetrics.height(lines: model.barLines, size: model.textSize.points, secondaryRow: model.showsSecondaryRow))
        case .panel:
            let size = NSSize(width: 480, height: min(600, area.height * 0.7))
            return NSRect(x: area.maxX - size.width - 24, y: area.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private func key(for mode: DisplayMode) -> String { "overlayFrame.\(mode.rawValue)" }

    private func saveFrame() {
        guard !applyingFrame, !dodging else { return }
        if let expected = programmaticFrame, abs(expected.minX - panel.frame.minX) < 1, abs(expected.minY - panel.frame.minY) < 1,
           abs(expected.width - panel.frame.width) < 1, abs(expected.height - panel.frame.height) < 1 { return }
        programmaticFrame = nil
        // The person dragged the bar: where it is now is home.
        if dodged { dodged = false; homeFrame = nil }
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
