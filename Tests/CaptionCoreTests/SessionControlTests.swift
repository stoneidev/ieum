import Testing
@testable import CaptionCore

@Suite("Session control (mid-run settings restart)")
struct SessionControlTests {

    @Test func startThenStopReturnsToIdle() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.phase == .live)
        #expect(control.requestStop())
        #expect(control.phase == .stopping)
        #expect(control.noteSessionEnded() == false)
        #expect(control.phase == .idle)
    }

    @Test func startWhileLiveIsIgnored() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestStart() == false)
        #expect(control.phase == .live)
    }

    @Test func stopWhileIdleDoesNothing() {
        var control = SessionControl()
        #expect(control.requestStop() == false)
        #expect(control.phase == .idle)
    }

    @Test func restartWhileLiveStopsOnceThenStartsAgain() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestRestart())
        #expect(control.phase == .stopping)
        #expect(control.restartAfterStop)
        #expect(control.generation == 1)
        #expect(control.noteSessionEnded())
        #expect(control.phase == .idle)
        #expect(control.requestStart())
        #expect(control.phase == .live)
    }

    @Test func overlappingRestartsCoalesceIntoOneRerun() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestRestart())
        // Second settings change while the first stop is still running: do not halt again.
        #expect(control.requestRestart() == false)
        #expect(control.phase == .stopping)
        #expect(control.restartAfterStop)
        #expect(control.generation == 2)
        #expect(control.noteSessionEnded())
        #expect(control.requestStart())
        #expect(control.phase == .live)
        #expect(control.restartAfterStop == false)
    }

    @Test func userStopCancelsPendingRestart() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestRestart())
        // User pressed stop while the settings restart was winding down.
        #expect(control.requestStop() == false)
        #expect(control.restartAfterStop == false)
        #expect(control.phase == .stopping)
        #expect(control.noteSessionEnded() == false)
        #expect(control.phase == .idle)
    }

    @Test func restartWhileIdleIsIgnored() {
        var control = SessionControl()
        #expect(control.requestRestart() == false)
        #expect(control.phase == .idle)
        #expect(control.restartAfterStop == false)
    }

    @Test func stopWhileAlreadyStoppingIsIdempotent() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestStop())
        #expect(control.requestStop() == false)
        #expect(control.phase == .stopping)
        #expect(control.noteSessionEnded() == false)
    }

    @Test func restartDuringUserStopDoesNotReviveSession() {
        var control = SessionControl()
        #expect(control.requestStart())
        #expect(control.requestStop())
        // Status is still "running" in the UI until the task ends, so a settings observer might
        // still ask to restart — that must not undo the user's stop.
        #expect(control.requestRestart() == false)
        #expect(control.restartAfterStop == false)
        #expect(control.noteSessionEnded() == false)
        #expect(control.phase == .idle)
    }
}
