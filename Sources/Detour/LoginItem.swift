import Foundation
import ServiceManagement
import DetourCore

/// Open at Login, as a LaunchAgent that opens this copy of the app.
enum LoginItem {
    /// Whether launchd restarts the app after a crash.
    static let restartsAfterCrash = false
    private static let agent = LaunchAgent(label: bundleID, restartsAfterCrash: restartsAfterCrash)

    /// Whether the agent is installed. It may still be switched off in System Settings.
    static var isEnabled: Bool { agent.exists }

    /// Whether the agent is installed but switched off under General › Login Items.
    static var needsApproval: Bool {
        isEnabled && SMAppService.statusForLegacyPlist(at: agent.url) == .requiresApproval
    }

    /// Why Open at Login can't be turned on for this copy, or nil if it can.
    static var problem: String? { LaunchAgent.problem(bundlePath: Bundle.main.bundlePath) }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try agent.write(executable: executablePath) } else { try agent.remove() }
    }

    /// Rewrites the agent so it points at this copy of the app, e.g. after it was moved.
    static func refresh() {
        if isEnabled, problem == nil { try? agent.write(executable: executablePath) }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    private static var executablePath: String { Bundle.main.bundlePath + "/Contents/MacOS/Detour" }
}
