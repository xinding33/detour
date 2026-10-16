import Foundation

/// What the menu bar icon and the top of the menu say. The icon is Detour's only feedback.
public struct Summary: Equatable, Sendable {
    public enum Icon: Equatable, Sendable {
        /// Traffic goes through Tailscale as usual, or Detour has nothing to undo.
        case watching
        /// Tailscale is off because of a watched app, including during the grace period.
        case detouring
        case paused
        /// Detour can't control Tailscale right now.
        case problem
    }

    public enum Fix: Equatable, Sendable {
        case openTailscale, getTailscale
    }

    public var title: String
    public var detail: String
    public var icon: Icon
    public var fix: Fix?

    public init(title: String, detail: String, icon: Icon, fix: Fix? = nil) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.fix = fix
    }

    public struct Inputs: Sendable {
        public var session: Session?
        public var configured: [WatchedApp]
        public var tailscale: TailscaleState
        public var pause: Pause?
        public var graceSeconds: Int
        /// The last command's error, until a command succeeds.
        public var lastError: String?
        public var now: Date
        /// Formats a time of day, e.g. "2:31 PM".
        public var time: @Sendable (Date) -> String

        public init(session: Session?, configured: [WatchedApp], tailscale: TailscaleState, pause: Pause? = nil,
                    graceSeconds: Int = Configuration.defaultGraceSeconds, lastError: String? = nil, now: Date,
                    time: @escaping @Sendable (Date) -> String) {
            self.session = session
            self.configured = configured
            self.tailscale = tailscale
            self.pause = pause
            self.graceSeconds = graceSeconds
            self.lastError = lastError
            self.now = now
            self.time = time
        }
    }

    public static func make(_ inputs: Inputs) -> Summary {
        if let pause = inputs.pause, pause.isActive(at: inputs.now) {
            // Pausing hands Tailscale back. Until that has worked, say so rather than "paused".
            if inputs.session?.origin == .turnedOff {
                if let problem = problem(inputs) { return problem }
                return Summary(title: "Turning Tailscale back on…", detail: "Then Detour pauses.", icon: .detouring)
            }
            let title = switch pause {
            case .until(let end): "Detour is paused until \(inputs.time(end))"
            case .untilResumed: "Detour is paused"
            }
            let detail = switch inputs.tailscale {
            case .on: "Tailscale is on and won't be touched."
            case .off: "Tailscale is off and won't be touched."
            default: "Tailscale won't be touched."
            }
            return Summary(title: title, detail: detail, icon: .paused)
        }

        if let problem = problem(inputs) { return problem }

        guard let session = inputs.session else {
            let title = switch inputs.tailscale {
            case .on: "Tailscale is on"
            case .off: "Tailscale is off"
            default: "Checking Tailscale…"
            }
            let detail = inputs.configured.isEmpty
                ? "Choose apps to watch in Settings."
                : "Watching \(list(inputs.configured.map(\.name)))"
            return Summary(title: title, detail: detail, icon: .watching)
        }

        let names = list(session.apps)
        let quits = session.apps.count == 1 ? "quits" : "quit"
        switch session.origin {
        case .waiting:
            return Summary(title: "Checking Tailscale…", detail: "\(names) is open.", icon: .watching)
        case .turnedOff:
            if let quit = session.lastQuit {
                let remaining = Int((quit.timeIntervalSince(inputs.now) + TimeInterval(inputs.graceSeconds)).rounded(.up))
                let title = remaining > 0 ? "Turning Tailscale on in \(remaining) s" : "Turning Tailscale on…"
                let reopen = session.apps.count == 1 ? "Reopening it cancels this." : "Reopening one cancels this."
                return Summary(title: title, detail: "\(names) quit. \(reopen)", icon: .detouring)
            }
            let after = session.apps.count == 1 ? "it quits" : "they quit"
            let when = inputs.graceSeconds == 0
                ? "Turns back on when \(after)."
                : "Turns back on \(inputs.graceSeconds) s after \(after)."
            return Summary(title: "Tailscale is off for \(names)",
                           detail: "Since \(inputs.time(session.started)). \(when)", icon: .detouring)
        case .alreadyOff:
            return Summary(title: "Tailscale was already off",
                           detail: "Detour will leave it off after \(names) \(quits).", icon: .watching)
        case .userTurnedOn:
            return Summary(title: "You turned Tailscale back on",
                           detail: "Detour will leave it alone until \(names) \(quits).", icon: .watching)
        }
    }

    private static func problem(_ inputs: Inputs) -> Summary? {
        let retry = "Detour retries every \(Int(Engine.retryInterval)) s."
        switch inputs.tailscale {
        case .notInstalled:
            return Summary(title: "Tailscale isn't installed",
                           detail: "Detour works with the standalone Tailscale app from tailscale.com.",
                           icon: .problem, fix: .getTailscale)
        case .needsLogin:
            return Summary(title: "Tailscale is logged out",
                           detail: "Log in to Tailscale and Detour picks it up.", icon: .problem, fix: .openTailscale)
        case .unreachable(let detail):
            return Summary(title: "Can't reach Tailscale", detail: "\(detail) \(retry)", icon: .problem,
                           fix: .openTailscale)
        case .unknown, .on, .off:
            break
        }
        if let error = inputs.lastError {
            let title = inputs.session?.origin == .turnedOff ? "Couldn't turn Tailscale on" : "Couldn't turn Tailscale off"
            return Summary(title: title, detail: "\(error) \(retry)", icon: .problem)
        }
        return nil
    }

    /// "A", "A and B", "A, B and C". More than three become "4 apps".
    public static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: "no apps"
        case 1: names[0]
        case 2, 3: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        default: "\(names.count) apps"
        }
    }
}

/// Timing shared by the app and the text it shows.
public enum Engine {
    /// How long after a failed command Detour tries again.
    public static let retryInterval: TimeInterval = 30
    /// How often Tailscale's state is checked while a session is open, to notice it being turned on by hand.
    public static let sessionPollInterval: TimeInterval = 5
    /// How often it's checked otherwise, for the menu and Settings.
    public static let idlePollInterval: TimeInterval = 30
}
