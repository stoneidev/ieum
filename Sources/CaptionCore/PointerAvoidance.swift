import CoreGraphics
import Foundation

/// What the subtitle bar does when the pointer comes near it, so it never stands between a person and the window underneath.
public enum PointerAvoidance: String, CaseIterable, Sendable {
    /// Turns see-through and lets clicks pass to the window behind, until the pointer leaves.
    case fade
    /// Moves to the opposite edge of the screen (bottom to top, top to bottom), and back when the pointer follows.
    case dodge
    case off
}

/// The geometry of that behaviour, kept apart from the window so it can be tested. Coordinates are AppKit's (origin bottom left).
public struct PointerZone: Equatable, Sendable {
    /// How far outside the bar the pointer counts as near when it arrives, and how far it must go to count as gone
    /// (a larger distance, so the bar does not flicker at its edge).
    public var arriveMargin: CGFloat = 6
    public var leaveMargin: CGFloat = 28
    /// The right end of the bar holds its controls (text size, panel, menu). The pointer there is meant for the bar.
    public var controlsWidth: CGFloat = 170

    public init() {}

    /// Whether the pointer is near the words of the bar. `wasNear` makes leaving harder than arriving.
    public func isNear(pointer: CGPoint, bar: CGRect, wasNear: Bool) -> Bool {
        let margin = wasNear ? leaveMargin : arriveMargin
        let area = bar.insetBy(dx: -margin, dy: -margin)
        guard area.contains(pointer) else { return false }
        // The controls keep working: over them the bar stays solid.
        let controls = CGRect(x: bar.maxX - controlsWidth, y: bar.minY, width: controlsWidth, height: bar.height)
        return !controls.contains(pointer)
    }

    /// The bar moved to the opposite edge of `screen`, same size and horizontal place: above the bottom edge becomes
    /// below the top edge, and the other way round. `gap` is the distance kept from the edge.
    public static func opposite(of bar: CGRect, in screen: CGRect, gap: CGFloat = 56) -> CGRect {
        var moved = bar
        let inLowerHalf = bar.midY < screen.midY
        moved.origin.y = inLowerHalf ? screen.maxY - bar.height - gap : screen.minY + gap
        return moved
    }
}
