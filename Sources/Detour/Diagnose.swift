import AppKit
import DetourCore

/// `Detour --diagnose` prints what an agent or a bug report needs, then exits. It only reads:
/// it never changes Tailscale or settings.
enum Diagnose {
    static func run() -> Never {
        let app = Bundle.main.bundleURL
        let configuration = JSONStore<Configuration>(url: supportURL.appendingPathComponent("settings.json"))
        let sessionFile = supportURL.appendingPathComponent("session.json")
        let config = configuration.load()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let tailscale = TailscaleClient.statusNow()
        var lines = [
            "\(appName) \(appVersion) at \(app.path)",
            "Bundle identifier: \(bundleID)",
            "Release build: \(Updater.isRelease(app) ? "yes" : "no")",
            "Developer ID signed: \(Updater.isDeveloperIDSigned(app) ? "yes" : "no")",
            "Installs updates: \(Updater.canInstallUpdates(into: app) ? "yes" : "no")",
            "Open at Login: \(LoginItem.needsApproval ? "switched off in System Settings" : LoginItem.isEnabled ? "on" : "off")"
                + (LoginItem.problem.map { " (\($0))" } ?? ""),
            "Tailscale app: \(TailscaleClient.appURL?.path ?? "not installed (needs \(TailscaleApp.bundleID))")",
            "Tailscale: \(describe(tailscale))",
            "Settings: \(configuration.url.path)"
                + (configuration.loadError.map { " (unreadable: \($0.localizedDescription))" } ?? ""),
        ]
        if let config {
            lines.append("Wait before reconnecting: \(config.graceSeconds) s")
            lines.append("Watched apps:" + (config.apps.isEmpty ? " none" : ""))
            for watched in config.apps {
                lines.append("  \(watched.name) (\(watched.bundleID)): \(running.contains(watched.bundleID) ? "open" : "not open")"
                    + (AppInfo.url(for: watched.bundleID) == nil ? ", not installed" : ""))
            }
        }
        if let data = try? Data(contentsOf: sessionFile), let text = String(data: data, encoding: .utf8) {
            lines.append("Session (\(sessionFile.path)):")
            lines.append(text)
        } else {
            lines.append("Session: none")
        }
        print(lines.joined(separator: "\n"))
        exit(0)
    }

    private static func describe(_ status: TailscaleStatus) -> String {
        let state = switch status.state {
        case .unknown: "unknown"
        case .on: "on"
        case .off: "off"
        case .needsLogin: "logged out"
        case .notInstalled: "not installed"
        case .unreachable(let detail): "unreachable (\(detail))"
        }
        return [status.version, state].compactMap { $0 }.joined(separator: ", ")
    }
}
