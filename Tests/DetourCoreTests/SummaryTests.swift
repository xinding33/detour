import Foundation
import Testing
@testable import DetourCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let apps = [KnownApps.geForceNow, WatchedApp(bundleID: "net.battle.app", name: "Battle.net")]

private func summary(_ session: Session?, _ tailscale: TailscaleState = .on, pause: Pause? = nil,
                     lastError: String? = nil, at seconds: TimeInterval = 0) -> Summary {
    Summary.make(Summary.Inputs(session: session, configured: apps, tailscale: tailscale, pause: pause,
                                graceSeconds: 10, lastError: lastError, now: t0 + seconds,
                                time: { "T+\(Int($0.timeIntervalSince(t0)))" }))
}

@Suite struct SummaryTests {
    @Test func watching() {
        #expect(summary(nil) == Summary(title: "Tailscale is on", detail: "Watching GeForce NOW and Battle.net",
                                        icon: .watching))
    }

    @Test func noAppsChosen() {
        let s = Summary.make(Summary.Inputs(session: nil, configured: [], tailscale: .off, now: t0, time: { _ in "" }))
        #expect(s.title == "Tailscale is off")
        #expect(s.detail == "Choose apps to watch in Settings.")
    }

    @Test func detouring() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"])
        #expect(summary(session, .off, at: 60) == Summary(
            title: "Tailscale is off for GeForce NOW",
            detail: "Since T+0. Turns back on 10 s after it quits.", icon: .detouring))
    }

    @Test func gracePeriodCountsDown() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"], lastQuit: t0 + 100)
        #expect(summary(session, .off, at: 103) == Summary(
            title: "Turning Tailscale on in 7 s", detail: "GeForce NOW quit. Reopening it cancels this.",
            icon: .detouring))
        #expect(summary(session, .off, at: 110).title == "Turning Tailscale on…")
    }

    @Test func manualOverride() {
        let session = Session(origin: .userTurnedOn, started: t0, apps: ["GeForce NOW"])
        #expect(summary(session) == Summary(
            title: "You turned Tailscale back on",
            detail: "Detour will leave it alone until GeForce NOW quits.", icon: .watching))
    }

    @Test func paused() {
        let s = summary(nil, pause: .until(t0 + 3600), at: 10)
        #expect(s == Summary(title: "Detour is paused until T+3600", detail: "Tailscale is on and won't be touched.",
                             icon: .paused))
        #expect(summary(nil, pause: .until(t0 + 3600), at: 3600).icon == .watching)
        #expect(summary(nil, .off, pause: .untilResumed).title == "Detour is paused")
    }

    @Test func problems() {
        let unreachable = summary(nil, .unreachable("Tailscale isn't running."))
        #expect(unreachable == Summary(title: "Can't reach Tailscale",
                                       detail: "Tailscale isn't running. Detour retries every 30 s.",
                                       icon: .problem, fix: .openTailscale))
        #expect(summary(nil, .notInstalled).fix == .getTailscale)
        #expect(summary(nil, .needsLogin).icon == .problem)
        let failedOn = summary(Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"]), .off, lastError: "boom")
        #expect(failedOn.title == "Couldn't turn Tailscale on")
        #expect(failedOn.icon == .problem)
    }

    @Test func pauseOutranksProblems() {
        #expect(summary(nil, .notInstalled, pause: .untilResumed).icon == .paused)
    }

    @Test func lists() {
        #expect(Summary.list(["A"]) == "A")
        #expect(Summary.list(["A", "B"]) == "A and B")
        #expect(Summary.list(["A", "B", "C"]) == "A, B and C")
        #expect(Summary.list(["A", "B", "C", "D"]) == "4 apps")
    }

    @Test func pausingShowsTheHandBackUntilItWorks() {
        let session = Session(origin: .turnedOff, started: t0, apps: ["GeForce NOW"])
        let pending = summary(session, .off, pause: .untilResumed)
        #expect(pending.title == "Turning Tailscale back on…")
        #expect(pending.icon == .detouring)
        let failed = summary(session, .off, pause: .untilResumed, lastError: "boom")
        #expect(failed.title == "Couldn't turn Tailscale on")
        #expect(failed.icon == .problem)
    }
}
