import AppKit

// Command-line modes run before AppKit starts, so they work over SSH and from agents.
if CommandLine.arguments.contains("--diagnose") {
    Diagnose.run()
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshot.run(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
