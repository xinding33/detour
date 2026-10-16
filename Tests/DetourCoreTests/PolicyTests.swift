import Foundation
import Testing
@testable import DetourCore

private let gfn = KnownApps.geForceNow
private let battleNet = WatchedApp(bundleID: "net.battle.app", name: "Battle.net")
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func inputs(_ open: [WatchedApp], _ tailscale: TailscaleState, at seconds: TimeInterval = 0,
                    paused: Bool = false, blocked: Action? = nil) -> Policy.Inputs {
    Policy.Inputs(open: open, tailscale: tailscale, paused: paused, grace: 10, blocked: blocked,
                  now: t0 + seconds)
}

@Suite struct PolicyTests {
    @Test func nothingHappensWithoutAWatchedApp() {
        #expect(Policy.step(nil, inputs([], .on)) == Policy.Step(session: nil))
        #expect(Policy.step(nil, inputs([], .off)) == Policy.Step(session: nil))
    }

    @Test func openingAWatchedAppTurnsTailscaleOff() {
        let step = Policy.step(nil, inputs([gfn], .on))
        #expect(step.action == .turnOff)
        #expect(step.session == Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"]))
    }

    @Test func tailscaleThatWasAlreadyOffStaysOffAfterwards() {
        var step = Policy.step(nil, inputs([gfn], .off))
        #expect(step.action == nil)
        #expect(step.session?.origin == .alreadyOff)
        step = Policy.step(step.session, inputs([], .off, at: 60))
        #expect(step.action == nil)
        step = Policy.step(step.session, inputs([], .off, at: 71))
        #expect(step == Policy.Step(session: nil))
    }

    @Test func waitsForTailscaleBeforeDeciding() {
        var step = Policy.step(nil, inputs([gfn], .unknown))
        #expect(step.action == nil)
        #expect(step.session?.origin == .waiting)
        step = Policy.step(step.session, inputs([gfn], .unreachable("x"), at: 5))
        #expect(step.action == nil)
        step = Policy.step(step.session, inputs([gfn], .on, at: 10))
        #expect(step.action == .turnOff)
        #expect(step.session?.started == t0)
    }

    @Test func turnsBackOnOnlyAfterEveryWatchedAppQuitAndTheGracePeriod() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        var step = Policy.step(session, inputs([gfn, battleNet], .off, at: 30))
        #expect(step.action == nil)
        session = step.session
        step = Policy.step(session, inputs([battleNet], .off, at: 40))
        #expect(step.action == nil)
        #expect(step.session?.lastQuit == nil)
        session = step.session
        step = Policy.step(session, inputs([], .off, at: 50))
        #expect(step.action == nil)
        #expect(step.session?.lastQuit == t0 + 50)
        #expect(step.session?.apps == ["Battle.net"])
        session = step.session
        step = Policy.step(session, inputs([], .off, at: 59))
        #expect(step.action == nil)
        step = Policy.step(step.session, inputs([], .off, at: 60))
        #expect(step.action == .turnOn)
        #expect(Policy.finished(.turnOn, .ran(succeeded: true, readBack: .on), session: step.session) == nil)
    }

    @Test func reopeningDuringTheGracePeriodCancelsIt() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        session = Policy.step(session, inputs([], .off, at: 100)).session
        #expect(session?.lastQuit == t0 + 100)
        var step = Policy.step(session, inputs([gfn], .off, at: 105))
        #expect(step.action == nil)
        #expect(step.session?.lastQuit == nil)
        #expect(step.session?.origin == .turnedOff)
        step = Policy.step(step.session, inputs([gfn], .off, at: 200))
        #expect(step.action == nil)
    }

    @Test func zeroGraceTurnsBackOnAtOnce() {
        let session = Policy.step(nil, inputs([gfn], .on)).session
        var quit = inputs([], .off, at: 100)
        quit.grace = 0
        #expect(Policy.step(session, quit).action == .turnOn)
    }

    @Test func turningTailscaleOnByHandIsLeftAloneUntilTheSessionEnds() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        var step = Policy.step(session, inputs([gfn], .on, at: 60))
        #expect(step.action == nil)
        #expect(step.session?.origin == .userTurnedOn)
        session = step.session
        // Off by hand again: still the user's business.
        step = Policy.step(session, inputs([gfn], .off, at: 70))
        #expect(step.action == nil)
        #expect(step.session?.origin == .userTurnedOn)
        // Quitting doesn't reconnect.
        step = Policy.step(step.session, inputs([], .off, at: 80))
        #expect(step.action == nil)
        step = Policy.step(step.session, inputs([], .off, at: 95))
        #expect(step == Policy.Step(session: nil))
    }

    @Test func aQuickRelaunchAfterTurningItOnByHandDoesNotTurnItOff() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        session = Policy.step(session, inputs([gfn], .on, at: 60)).session
        session = Policy.step(session, inputs([], .on, at: 70)).session
        let step = Policy.step(session, inputs([gfn], .on, at: 75))
        #expect(step.action == nil)
        #expect(step.session?.origin == .userTurnedOn)
    }

    @Test func turningItOnByHandDuringTheGracePeriodEndsTheSession() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        session = Policy.step(session, inputs([], .off, at: 100)).session
        #expect(Policy.step(session, inputs([], .on, at: 103)) == Policy.Step(session: nil))
    }

    @Test func pausingHandsTailscaleBackImmediately() {
        let session = Policy.step(nil, inputs([gfn], .on)).session
        let step = Policy.step(session, inputs([gfn], .off, at: 30, paused: true))
        #expect(step.action == .turnOn)
    }

    @Test func pausingWithNothingToUndoEndsTheSession() {
        let session = Policy.step(nil, inputs([gfn], .off)).session
        #expect(Policy.step(session, inputs([gfn], .off, at: 30, paused: true)) == Policy.Step(session: nil))
    }

    @Test func pausedDetourDoesNothing() {
        #expect(Policy.step(nil, inputs([gfn], .on, paused: true)) == Policy.Step(session: nil))
    }

    @Test func endingThePauseWithAWatchedAppOpenTurnsTailscaleOff() {
        #expect(Policy.step(nil, inputs([gfn], .on, at: 3600)).action == .turnOff)
    }

    @Test func aFailedTurnOffIsRetriedOnlyWhenAllowed() {
        let step = Policy.step(nil, inputs([gfn], .on))
        let session = Policy.finished(.turnOff, .ran(succeeded: false, readBack: .on), session: step.session)
        #expect(session?.origin == .waiting)
        // Still on, and not mistaken for the user turning it on.
        var retry = Policy.step(session, inputs([gfn], .on, at: 5, blocked: .turnOff))
        #expect(retry.action == nil)
        #expect(retry.session?.origin == .waiting)
        retry = Policy.step(retry.session, inputs([gfn], .on, at: 30))
        #expect(retry.action == .turnOff)
    }

    @Test func aFailedTurnOnIsRetried() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        session = Policy.step(session, inputs([], .off, at: 100)).session
        let step = Policy.step(session, inputs([], .off, at: 110))
        #expect(step.action == .turnOn)
        session = Policy.finished(.turnOn, .ran(succeeded: false, readBack: .unreachable("x")), session: step.session)
        #expect(session?.origin == .turnedOff)
        #expect(Policy.step(session, inputs([], .off, at: 120, blocked: .turnOn)).action == nil)
        #expect(Policy.step(session, inputs([], .off, at: 140)).action == .turnOn)
    }

    @Test func keepsThePromiseWhileTailscaleIsUnreachable() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        var step = Policy.step(session, inputs([], .unreachable("Tailscale isn't running."), at: 100))
        #expect(step.action == nil)
        #expect(step.session?.origin == .turnedOff)
        session = step.session
        step = Policy.step(session, inputs([], .off, at: 300))
        #expect(step.action == .turnOn)
    }

    /// After a crash or restart, the saved session turns Tailscale back on.
    @Test func aSavedSessionWithNoAppOpenReconnects() {
        let saved = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"])
        var step = Policy.step(saved, inputs([], .off, at: 3600))
        #expect(step.action == nil)
        step = Policy.step(step.session, inputs([], .off, at: 3610))
        #expect(step.action == .turnOn)
    }

    /// `down` may have worked even if reading the state back failed, so the promise stays.
    @Test func anUnreadableStateAfterTurningOffKeepsThePromise() {
        let step = Policy.step(nil, inputs([gfn], .on))
        for readBack in [TailscaleState.unreachable("Tailscale didn't answer."), .unknown, .off] {
            #expect(Policy.finished(.turnOff, .ran(succeeded: false, readBack: readBack), session: step.session)?.origin == .turnedOff)
        }
        let session = Policy.finished(.turnOff, .ran(succeeded: false, readBack: .unknown), session: step.session)
        let quit = Policy.step(session, inputs([], .off, at: 100))
        #expect(quit.session?.origin == .turnedOff)
        #expect(Policy.step(quit.session, inputs([], .off, at: 110)).action == .turnOn)
    }

    /// The user turned Tailscale off just before opening the app; the last read still says on.
    @Test func aNewSessionWaitsForAReadFromAfterItBegan() {
        let stale = Policy.Inputs(open: [gfn], tailscale: .on, tailscaleAsOf: t0 - 20, now: t0)
        let step = Policy.step(nil, stale)
        #expect(step.action == nil)
        #expect(step.session?.origin == .waiting)
        #expect(Policy.needsFreshStatus(step.session, stale))
        let fresh = Policy.Inputs(open: [gfn], tailscale: .off, tailscaleAsOf: t0 + 0.5, now: t0 + 1)
        #expect(!Policy.needsFreshStatus(step.session, fresh))
        let decided = Policy.step(step.session, fresh)
        #expect(decided.action == nil)
        #expect(decided.session?.origin == .alreadyOff)
    }

    @Test func aStaleOffDoesNotDecideEither() {
        let stale = Policy.Inputs(open: [gfn], tailscale: .off, tailscaleAsOf: t0 - 1, now: t0)
        #expect(Policy.step(nil, stale).session?.origin == .waiting)
    }

    @Test func removingTheOpenAppFromTheListEndsTheSession() {
        let session = Policy.step(nil, inputs([gfn], .on)).session
        var step = Policy.step(session, inputs([], .off, at: 50))
        #expect(step.session?.lastQuit == t0 + 50)
        step = Policy.step(step.session, inputs([], .off, at: 60))
        #expect(step.action == .turnOn)
    }

    @Test func aWatchedAppOpeningDuringTheGracePeriodAfterAFailedTurnOnKeepsTailscaleOff() {
        var session = Policy.step(nil, inputs([gfn], .on)).session
        session = Policy.step(session, inputs([], .off, at: 100)).session
        session = Policy.finished(.turnOn, .ran(succeeded: false, readBack: .off), session: Policy.step(session, inputs([], .off, at: 110)).session)
        let step = Policy.step(session, inputs([battleNet], .off, at: 115, blocked: .turnOn))
        #expect(step.action == nil)
        #expect(step.session?.origin == .turnedOff)
        #expect(step.session?.lastQuit == nil)
    }

    /// Decided on an older read, but the user turned Tailscale off before the command ran.
    @Test func aTurnOffSkippedBecauseItWasAlreadyOffIsNotDetours() {
        let step = Policy.step(nil, inputs([gfn], .on))
        let session = Policy.finished(.turnOff, .skipped(.off), session: step.session)
        #expect(session?.origin == .alreadyOff)
        var quit = Policy.step(session, inputs([], .off, at: 100))
        quit = Policy.step(quit.session, inputs([], .off, at: 200))
        #expect(quit == Policy.Step(session: nil))
    }

    @Test func aTurnOffSkippedBecauseTailscaleWasUnreachableWaits() {
        let step = Policy.step(nil, inputs([gfn], .on))
        #expect(Policy.finished(.turnOff, .skipped(.unreachable("x")), session: step.session)?.origin == .waiting)
    }

    @Test func aTurnOnSkippedBecauseItWasAlreadyOnEndsTheSession() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"], lastQuit: t0)
        #expect(Policy.finished(.turnOn, .skipped(.on), session: session) == nil)
        #expect(Policy.finished(.turnOn, .skipped(.needsLogin), session: session) == session)
    }

    @Test func outcomesThatRanUseTheReadBack() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"])
        #expect(Policy.finished(.turnOff, .ran(succeeded: true, readBack: .off), session: session) == session)
        #expect(Policy.finished(.turnOff, .ran(succeeded: false, readBack: .on), session: session)?.origin == .waiting)
        #expect(Policy.finished(.turnOn, .ran(succeeded: true, readBack: .on), session: session) == nil)
        #expect(Policy.finished(.turnOn, .ran(succeeded: false, readBack: .off), session: session) == session)
    }

    /// `down` worked, then the user turned Tailscale back on before it was read back.
    @Test func aReconnectBeforeTheReadBackIsTheUsers() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"])
        #expect(Policy.finished(.turnOff, .ran(succeeded: true, readBack: .on), session: session)?.origin == .userTurnedOn)
    }
}
