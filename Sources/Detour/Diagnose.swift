import ApplicationServices
import Foundation
import DetourCore

/// `Detour --diagnose` prints what an agent or a bug report needs, then exits. It only reads:
/// it never prompts for permissions or changes settings.
enum Diagnose {
    static func run() -> Never {
        let app = Bundle.main.bundleURL
        let lines = [
            "\(appName) \(appVersion) at \(app.path)",
            "Bundle identifier: \(bundleID)",
            "Release build: \(Updater.isRelease(app) ? "yes" : "no")",
            "Developer ID signed: \(Updater.isDeveloperIDSigned(app) ? "yes" : "no")",
            "Installs updates: \(Updater.canInstallUpdates(into: app) ? "yes" : "no")",
            "Open at Login: \(LoginItem.needsApproval ? "switched off in System Settings" : LoginItem.isEnabled ? "on" : "off")"
                + (LoginItem.problem.map { " (\($0))" } ?? ""),
            // Remove this line if the app doesn't need Accessibility. Run from a terminal, the
            // app has the terminal's grant, so this reports the terminal's.
            "Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")",
        ]
        print(lines.joined(separator: "\n"))
        exit(0)
    }
}
