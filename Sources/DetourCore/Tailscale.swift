import Foundation

/// What Detour knows about Tailscale.
public enum TailscaleState: Equatable, Sendable {
    /// Not checked yet.
    case unknown
    /// Connected, or connecting.
    case on
    /// Logged in, but switched off (`tailscale down`).
    case off
    /// Logged out, or the device is waiting for approval.
    case needsLogin
    /// The standalone Tailscale app isn't installed.
    case notInstalled
    /// The CLI couldn't reach Tailscale, usually because the app isn't running.
    case unreachable(String)

    /// Whether Detour can turn Tailscale on or off from here.
    public var isControllable: Bool { self == .on || self == .off }

    /// A problem worth a dimmed icon, or nil.
    public var problem: String? {
        switch self {
        case .unknown, .on, .off: nil
        case .needsLogin: "Tailscale needs you to log in."
        case .notInstalled: "The standalone Tailscale app isn't installed."
        case .unreachable(let detail): detail.isEmpty ? "Tailscale isn't running." : detail
        }
    }
}

/// The parts of `tailscale status --json` Detour reads.
public struct TailscaleStatus: Equatable, Sendable {
    public var state: TailscaleState
    /// The short version, e.g. "1.104.1".
    public var version: String?

    public init(state: TailscaleState, version: String? = nil) {
        self.state = state
        self.version = version
    }

    /// Parses the output of `tailscale status --json`. The CLI can print it even when it exits
    /// with a failure, so the exit status is only used when the output isn't JSON.
    public static func parse(output: Data, exitStatus: Int32, errorOutput: String) -> TailscaleStatus {
        struct Raw: Decodable {
            var BackendState: String?
            var Version: String?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: output), let backend = raw.BackendState else {
            return TailscaleStatus(state: .unreachable(describe(errorOutput: errorOutput, exitStatus: exitStatus)))
        }
        let version = raw.Version.map { String($0.prefix { $0 != "-" }) }
        let state: TailscaleState = switch backend {
        case "Running", "Starting": .on
        case "Stopped": .off
        case "NeedsLogin", "NeedsMachineAuth": .needsLogin
        case "InUseOtherUser": .unreachable("Another user on this Mac is using Tailscale.")
        default: .unreachable("Tailscale is starting up.")
        }
        return TailscaleStatus(state: state, version: version)
    }

    /// A sentence for a CLI failure.
    public static func describe(errorOutput: String, exitStatus: Int32) -> String {
        let text = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("is Tailscale running")
            || text.localizedCaseInsensitiveContains("failed to connect") {
            return "Tailscale isn't running."
        }
        if text.isEmpty { return "The Tailscale CLI failed (exit status \(exitStatus))." }
        // The first line is the useful one; later lines are usage text.
        return String(text.split(separator: "\n").first ?? Substring(text))
    }
}

/// Where the standalone Tailscale app keeps its CLI.
public enum TailscaleApp {
    /// The standalone build from tailscale.com. The Mac App Store build isn't supported.
    public static let bundleID = "io.tailscale.ipn.macsys"
    public static let downloadPage = URL(string: "https://tailscale.com/download/mac")!

    public static func cli(inApp app: URL) -> URL {
        app.appendingPathComponent("Contents/MacOS/Tailscale")
    }
}
