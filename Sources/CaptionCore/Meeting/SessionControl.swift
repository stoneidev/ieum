import Foundation

/// Pure coordinator for overlapping start / stop / restart while captions run.
///
/// Mid-session settings changes (language, source, microphone) stop capture and start it again. Spawning a new
/// unstructured `Task` per change races: `stop()` used to re-read `sessionTask` after an `await`, so one restart
/// could wait on the session the previous restart had just started — leaving silence, a hung stop, or a surprise
/// re-start when the user later pressed stop. This type coalesces those requests so at most one stop runs, and a
/// single start follows with the latest settings.
public struct SessionControl: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case live
        case stopping
    }

    public private(set) var phase: Phase = .idle
    /// After the in-flight stop finishes, start again (settings changed mid-run).
    public private(set) var restartAfterStop = false
    /// Bumped on every restart request; useful for logs and tests.
    public private(set) var generation = 0

    public init() {}

    public var isActive: Bool { phase != .idle }

    /// Begin a session if idle. Returns whether the caller should start capture now.
    public mutating func requestStart() -> Bool {
        guard phase == .idle else { return false }
        phase = .live
        restartAfterStop = false
        return true
    }

    /// End the session. Cancels a pending restart so a later start is not automatic.
    /// Returns whether the caller should halt capture now (false if already stopping or idle).
    public mutating func requestStop() -> Bool {
        restartAfterStop = false
        switch phase {
        case .idle:
            return false
        case .live:
            phase = .stopping
            return true
        case .stopping:
            return false
        }
    }

    /// Settings changed while captions should keep running: stop once, then start with the latest prefs.
    /// Returns whether the caller should begin halting capture now (false if a stop is already in flight — only the
    /// restart flag is set, so the in-flight stop's end starts again). A user stop in progress
    /// (`restartAfterStop == false`) is left alone so a late settings change cannot revive captions.
    public mutating func requestRestart() -> Bool {
        switch phase {
        case .idle:
            return false
        case .live:
            generation += 1
            phase = .stopping
            restartAfterStop = true
            return true
        case .stopping:
            guard restartAfterStop else { return false }
            generation += 1
            return false
        }
    }

    /// The session task finished. Returns whether the caller should start capture again.
    public mutating func noteSessionEnded() -> Bool {
        let shouldRestart = restartAfterStop
        restartAfterStop = false
        phase = .idle
        return shouldRestart
    }
}
