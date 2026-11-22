import Testing
@testable import CaptionCore

@Suite("Session control (mid-run settings restart)")
struct SessionControlTests {

    @Test func startThenStopReturnsToIdle() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        #expect(control.phase == .live)
        let stop = control.requestStop()
        #expect(stop)
        #expect(control.phase == .stopping)
        let restart = control.noteSessionEnded()
        #expect(restart == false)
        #expect(control.phase == .idle)
    }

    @Test func startWhileLiveIsIgnored() {
        var control = SessionControl()
        let first = control.requestStart()
        #expect(first)
        let second = control.requestStart()
        #expect(second == false)
        #expect(control.phase == .live)
    }

    @Test func stopWhileIdleDoesNothing() {
        var control = SessionControl()
        let stop = control.requestStop()
        #expect(stop == false)
        #expect(control.phase == .idle)
    }

    @Test func restartWhileLiveStopsOnceThenStartsAgain() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        let halt = control.requestRestart()
        #expect(halt)
        #expect(control.phase == .stopping)
        #expect(control.restartAfterStop)
        #expect(control.generation == 1)
        let shouldRestart = control.noteSessionEnded()
        #expect(shouldRestart)
        #expect(control.phase == .idle)
        let again = control.requestStart()
        #expect(again)
        #expect(control.phase == .live)
    }

    @Test func overlappingRestartsCoalesceIntoOneRerun() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        let firstHalt = control.requestRestart()
        #expect(firstHalt)
        // Second settings change while the first stop is still running: do not halt again.
        let secondHalt = control.requestRestart()
        #expect(secondHalt == false)
        #expect(control.phase == .stopping)
        #expect(control.restartAfterStop)
        #expect(control.generation == 2)
        let shouldRestart = control.noteSessionEnded()
        #expect(shouldRestart)
        let again = control.requestStart()
        #expect(again)
        #expect(control.phase == .live)
        #expect(control.restartAfterStop == false)
    }

    @Test func userStopCancelsPendingRestart() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        let halt = control.requestRestart()
        #expect(halt)
        // User pressed stop while the settings restart was winding down.
        let stop = control.requestStop()
        #expect(stop == false)
        #expect(control.restartAfterStop == false)
        #expect(control.phase == .stopping)
        let shouldRestart = control.noteSessionEnded()
        #expect(shouldRestart == false)
        #expect(control.phase == .idle)
    }

    @Test func restartWhileIdleIsIgnored() {
        var control = SessionControl()
        let halt = control.requestRestart()
        #expect(halt == false)
        #expect(control.phase == .idle)
        #expect(control.restartAfterStop == false)
    }

    @Test func stopWhileAlreadyStoppingIsIdempotent() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        let firstStop = control.requestStop()
        #expect(firstStop)
        let secondStop = control.requestStop()
        #expect(secondStop == false)
        #expect(control.phase == .stopping)
        let shouldRestart = control.noteSessionEnded()
        #expect(shouldRestart == false)
    }

    @Test func restartDuringUserStopDoesNotReviveSession() {
        var control = SessionControl()
        let started = control.requestStart()
        #expect(started)
        let stop = control.requestStop()
        #expect(stop)
        // Status is still "running" in the UI until the task ends, so a settings observer might
        // still ask to restart — that must not undo the user's stop.
        let halt = control.requestRestart()
        #expect(halt == false)
        #expect(control.restartAfterStop == false)
        let shouldRestart = control.noteSessionEnded()
        #expect(shouldRestart == false)
        #expect(control.phase == .idle)
    }
}
