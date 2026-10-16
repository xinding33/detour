import AppKit

/// Restarts the app, e.g. after an update replaced it. Not with `execv`: macOS 27 won't give the
/// same process a menu bar item twice, so the restarted app would have no icon.
@MainActor
enum Relaunch {
    /// Something has to outlive this process and open the new copy once it's gone. Through
    /// LaunchServices, so the new process stands for itself where permissions are concerned.
    /// Exiting with a failure for launchd's KeepAlive to restart (as Baton does) only works if the
    /// loaded job has KeepAlive, which the plist on disk doesn't prove.
    static func now() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", #"while kill -0 "$0" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -g "$1""#,
                            String(getpid()), Bundle.main.bundlePath]
        reopen.standardInput = FileHandle.nullDevice
        reopen.standardOutput = FileHandle.nullDevice
        reopen.standardError = FileHandle.nullDevice
        do {
            try reopen.run()
        } catch {
            log.error("Couldn't relaunch: \(error.localizedDescription, privacy: .public)")
            return
        }
        terminate()
    }

    /// `NSApp.terminate` called from inside a Task hangs, so start it from the run loop.
    static func terminate() {
        RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    }
}
