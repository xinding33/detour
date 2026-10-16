import AppKit
import Observation
import DetourCore

/// Wires the `Coordinator` to NSWorkspace and Tailscale: watches apps open and quit, polls
/// Tailscale, and runs the commands the coordinator asks for. Decisions and bookkeeping live in
/// the coordinator, where they're tested.
@MainActor @Observable
final class Controller {
    var configuration: Configuration {
        didSet {
            guard configuration != oldValue else { return }
            do { try configurationStore.save(configuration) } catch {
                log.error("Couldn't save settings: \(error.localizedDescription, privacy: .public)")
            }
            evaluate()
        }
    }
    private(set) var coordinator: Coordinator
    var session: Session? { coordinator.session }
    private(set) var tailscale = TailscaleStatus(state: .unknown)
    private(set) var pause: Pause?
    /// Bundle identifiers of every running app.
    private(set) var running: Set<String> = []
    /// Set to show the countdown second by second.
    @ObservationIgnored var menuIsOpen = false { didSet { if menuIsOpen { scheduleTick() } } }
    /// Called whenever what the menu bar shows may have changed.
    @ObservationIgnored var onChange: () -> Void = {}

    /// Whether Settings should open at launch, because there were no settings yet.
    @ObservationIgnored private(set) var isFirstLaunch = false

    @ObservationIgnored private let configurationStore: JSONStore<Configuration>
    @ObservationIgnored private let sessionStore: JSONStore<Session>
    @ObservationIgnored private let client = TailscaleClient()
    /// A controller for `--snapshot`: it shows states and never reads or changes Tailscale.
    @ObservationIgnored private let isPreview: Bool
    @ObservationIgnored private var polling = false
    /// Bumped when a command starts, so a status read from before it is thrown away.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastPoll = Date.distantPast
    /// When the read behind `tailscale` started.
    @ObservationIgnored private var tailscaleAsOf = Date.distantPast
    @ObservationIgnored private var quitDone: (@MainActor () -> Void)?
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(folder: URL, isPreview: Bool = false) {
        self.isPreview = isPreview
        configurationStore = JSONStore(url: folder.appendingPathComponent("settings.json"))
        sessionStore = JSONStore(url: folder.appendingPathComponent("session.json"))
        if let saved = configurationStore.load() {
            configuration = saved
        } else {
            var initial = Configuration()
            if configurationStore.loadError == nil {
                isFirstLaunch = true
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: KnownApps.geForceNow.bundleID) != nil {
                    initial.apps = [KnownApps.geForceNow]
                }
                try? configurationStore.save(initial)
            } else {
                log.error("Settings couldn't be read; using defaults without saving")
            }
            configuration = initial
        }
        let store = sessionStore
        let saved = store.load()
        coordinator = Coordinator(session: saved) { session in
            do {
                if let session { try store.save(session) } else { try store.remove() }
            } catch {
                log.error("Couldn't save the session: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        if let saved {
            log.info("Resuming a saved session (\(saved.origin.rawValue, privacy: .public))")
        }
    }

    var openWatched: [WatchedApp] { configuration.watched(running: running) }

    var summary: Summary {
        Summary.make(Summary.Inputs(
            session: session, configured: configuration.apps, tailscale: tailscale.state, pause: pause,
            graceSeconds: configuration.graceSeconds, lastError: coordinator.lastError, now: Date(),
            time: { $0.formatted(date: .omitted, time: .shortened) }))
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRunning() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.refreshRunning(excluding: pid) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        })
        refreshRunning()
        poll()
        scheduleTick()
    }

    /// For `--snapshot`: shows a state without polling Tailscale or acting on it.
    func preview(tailscale: TailscaleStatus, running: Set<String>) {
        self.tailscale = tailscale
        self.running = running
    }

    // MARK: Pause

    func pause(for duration: TimeInterval?) {
        pause = duration.map { .until(Date().addingTimeInterval($0)) } ?? .untilResumed
        log.info("Paused")
        evaluate()
    }

    func resume() {
        pause = nil
        log.info("Resumed")
        evaluate()
    }

    private var isPaused: Bool { pause?.isActive(at: Date()) ?? false }

    // MARK: Inputs

    private func refreshRunning(excluding pid: pid_t? = nil) {
        // A quit app can still be listed while its termination notification is delivered.
        let now = Set(NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.processIdentifier != pid }
            .compactMap(\.bundleIdentifier))
        guard now != running else { return }
        running = now
        evaluate()
    }

    private var busy: Bool { coordinator.running != nil }

    /// Reads Tailscale's state. Results from before a command finished are dropped.
    func poll() {
        guard !isPreview, !polling, !busy, !coordinator.isQuitting else { return }
        polling = true
        let generation = generation, started = Date()
        Task {
            let status = await client.status()
            polling = false
            guard generation == self.generation, !busy, !coordinator.isQuitting else { return }
            lastPoll = Date()
            tailscaleAsOf = started
            if status != tailscale { tailscale = status }
            evaluate()
        }
    }

    // MARK: Deciding

    private func evaluate() {
        defer { onChange() }
        guard !isPreview else { return }
        let now = Date()
        if let pause, !pause.isActive(at: now) { self.pause = nil }
        let inputs = Policy.Inputs(
            open: openWatched, tailscale: tailscale.state, tailscaleAsOf: tailscaleAsOf, paused: isPaused,
            grace: TimeInterval(configuration.graceSeconds), now: now)
        handle(coordinator.evaluate(inputs))
        // A new session decides on a read from after it began.
        if !busy, Policy.needsFreshStatus(session, inputs) { poll() }
        scheduleTick()
    }

    private func handle(_ effect: Coordinator.Effect?) {
        switch effect {
        case .run(let action): run(action)
        case .quit:
            let done = quitDone
            quitDone = nil
            // Never before `applicationShouldTerminate` has returned.
            Task { done?() }
        case nil: break
        }
    }

    private func run(_ action: Action) {
        generation += 1
        let started = Date()
        log.info("Turning Tailscale \(action == .turnOff ? "off" : "on", privacy: .public) for \(Summary.list(self.session?.apps ?? []), privacy: .public)")
        Task {
            let (error, outcome, status) = await client.perform(action)
            lastPoll = Date()
            tailscaleAsOf = started
            tailscale = status
            let next = coordinator.finished(action, outcome, error: error, now: Date())
            if coordinator.isQuitting { handle(next) } else { evaluate() }
        }
    }

    // MARK: Quitting

    func mustWaitBeforeQuitting(handBack: Bool) -> Bool {
        !isPreview && coordinator.mustWaitBeforeQuitting(handBack: handBack)
    }

    /// Waits for a running command, then hands Tailscale back if `handBack` and Detour turned it
    /// off. Calls `done` afterwards, never before returning.
    func shutDown(handBack: Bool, _ done: @escaping @MainActor () -> Void) {
        quitDone = done
        handle(coordinator.quit(handBack: handBack))
    }

    // MARK: Timer

    /// One-shot and rescheduled each time: every second while there's a countdown to show,
    /// otherwise every few seconds. A DispatchSourceTimer, because run-loop timers pause while
    /// the menu is open.
    private func scheduleTick() {
        let fast = menuIsOpen || session?.lastQuit != nil || coordinator.cooldown != nil
        let interval: TimeInterval = fast ? 1 : 5
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
            timer.resume()
            self.timer = timer
        }
        timer?.schedule(deadline: .now() + interval, leeway: .milliseconds(fast ? 100 : 1000))
    }

    private func tick() {
        let interval = session == nil ? Engine.idlePollInterval : Engine.sessionPollInterval
        if Date().timeIntervalSince(lastPoll) >= interval || (coordinator.cooldown.map { Date() >= $0.until } ?? false) {
            poll()
        }
        evaluate()
    }
}
