import AppKit
import DetourCore

/// Installs new releases from GitHub: at most one check a day, and only into a release build
/// signed with the same Developer ID.
@MainActor
final class Updates {
    let canInstall = Updater.canInstallUpdates(into: Bundle.main.bundleURL)
    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: "autoUpdate"); checkAutomatically() }
    }
    /// What the updater is doing, or nil when it is idle.
    private(set) var status: String?

    private var lastCheck: Date {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }
    private var timer: DispatchSourceTimer?

    init() {
        automatic = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
    }

    func start() {
        // A DispatchSourceTimer, because run-loop timers pause while a menu is open.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 60 * 60)
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.checkAutomatically() } }
        timer.resume()
        self.timer = timer
    }

    func checkAutomatically() {
        guard automatic, canInstall, status == nil, Date().timeIntervalSince(lastCheck) > 24 * 60 * 60 else { return }
        status = "Checking for updates…"
        Task {
            defer { status = nil }
            // A failed check is retried within the hour; a failed install at the next daily check.
            do { if let release = try await newerRelease() { try await install(release) } }
            catch { log.error("Automatic update failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func checkNow() {
        guard status == nil else { return }
        status = "Checking for updates…"
        Task {
            defer { status = nil }
            do {
                let release = try await newerRelease()
                let alert = NSAlert()
                guard let release else {
                    alert.messageText = "\(appName) is up to date"
                    alert.informativeText = "Version \(appVersion) is the latest."
                    await show(alert)
                    return
                }
                alert.messageText = "\(appName) \(release.version) is available"
                alert.informativeText = canInstall
                    ? "You have version \(appVersion)."
                    : "You have version \(appVersion). This copy wasn't installed from a release, so it can't update itself."
                if canInstall { alert.addButton(withTitle: "Install and Restart") }
                alert.addButton(withTitle: "Release Notes")
                alert.addButton(withTitle: "Later")
                switch (await show(alert), canInstall) {
                case (.alertFirstButtonReturn, true): try await install(release)
                case (.alertFirstButtonReturn, false), (.alertSecondButtonReturn, true): NSWorkspace.shared.open(release.page)
                default: break
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't update \(appName)"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                await show(alert)
            }
        }
    }

    /// Runs `alert` from the run loop rather than inside this task. A modal run inside a main-actor
    /// task holds the actor, so the rest of the app's tasks would wait until it's dismissed.
    @discardableResult
    private func show(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    NSApp.activate()
                    continuation.resume(returning: alert.runModal())
                }
            }
        }
    }

    private func newerRelease() async throws -> Release? {
        let release = try await Updater.latestRelease()
        lastCheck = Date()
        return release.version > appVersion ? release : nil
    }

    private func install(_ release: Release) async throws {
        status = "Installing \(appName) \(release.version)…"
        try await Updater.install(release, replacing: Bundle.main.bundleURL)
        log.info("Installed \(release.version.description, privacy: .public), relaunching")
        Relaunch.now()
    }
}
