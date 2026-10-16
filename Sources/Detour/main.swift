import AppKit

// Command-line modes run before AppKit starts, so they work over SSH and from agents.
if CommandLine.arguments.contains("--diagnose") {
    Diagnose.run()
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
