import Foundation

/// Open at Login is a LaunchAgent in ~/Library/LaunchAgents that opens this copy of the app. It's a
/// plain file, so tests can write it to a temporary folder, and it can restart the app after a crash.
public struct LaunchAgent: Sendable {
    public let label: String
    public let url: URL
    /// Restart the app if it exits with a failure (not after Quit). Leave this off when a crash
    /// should leave things as macOS had them, as Wink does with displays.
    public let restartsAfterCrash: Bool

    public init(label: String, restartsAfterCrash: Bool = false,
                directory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/LaunchAgents", isDirectory: true)) {
        self.label = label
        self.restartsAfterCrash = restartsAfterCrash
        url = directory.appendingPathComponent("\(label).plist")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func propertyList(executable: String) -> [String: Any] {
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            // Lists the app by name under Login Items in System Settings.
            "AssociatedBundleIdentifiers": label,
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        if restartsAfterCrash {
            plist["KeepAlive"] = ["SuccessfulExit": false]
            plist["ThrottleInterval"] = 5
        }
        return plist
    }

    public func write(executable: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: propertyList(executable: executable), format: .xml, options: 0)
            .write(to: url)
    }

    public func remove() throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Why this copy of the app must not own the login item, or nil if it may.
    public static func problem(bundlePath: String) -> String? {
        if bundlePath.contains("/AppTranslocation/") {
            return "Move the app to Applications first. macOS is running it from a temporary copy."
        }
        if !bundlePath.hasSuffix(".app") {
            return "Only a copy inside an .app bundle can open at login."
        }
        return nil
    }
}
