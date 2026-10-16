import Foundation

/// An app that turns Tailscale off while it's open. Matched by bundle identifier, so renaming or
/// moving the app doesn't break the rule.
public struct WatchedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    /// The name it had when it was added, shown if the app is no longer installed.
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// What the user chose in Settings.
public struct Configuration: Codable, Equatable, Sendable {
    public static let defaultGraceSeconds = 10
    public static let graceRange = 0...300

    public var apps: [WatchedApp]
    /// How long after the last watched app quits Tailscale goes back on.
    public var graceSeconds: Int

    public init(apps: [WatchedApp] = [], graceSeconds: Int = Configuration.defaultGraceSeconds) {
        self.apps = apps
        self.graceSeconds = graceSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([WatchedApp].self, forKey: .apps) ?? []
        graceSeconds = try container.decodeIfPresent(Int.self, forKey: .graceSeconds) ?? Configuration.defaultGraceSeconds
    }

    /// Adds apps that aren't in the list yet, keeping the list's order.
    public mutating func add(_ new: [WatchedApp]) {
        for app in new where !apps.contains(where: { $0.bundleID == app.bundleID }) {
            apps.append(app)
        }
    }

    public mutating func remove(bundleIDs: Set<String>) {
        apps.removeAll { bundleIDs.contains($0.bundleID) }
    }

    /// The configured apps whose bundle identifier is in `running`, in the list's order.
    public func watched(running: Set<String>) -> [WatchedApp] {
        apps.filter { running.contains($0.bundleID) }
    }
}

/// A Codable value in one JSON file, written atomically. If the file exists but can't be read, the
/// store refuses to save, so a newer version's file or a damaged one is never overwritten.
public final class JSONStore<Value: Codable>: @unchecked Sendable {
    public let url: URL
    public private(set) var loadError: Error?

    public init(url: URL) {
        self.url = url
    }

    /// The stored value, nil if there's no file yet or it can't be read.
    public func load() -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let value = try JSONDecoder.detour.decode(Value.self, from: Data(contentsOf: url))
            loadError = nil
            return value
        } catch {
            loadError = error
            return nil
        }
    }

    public func save(_ value: Value) throws {
        if let loadError { throw StoreError.unreadable(url, loadError) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.detour.encode(value).write(to: url, options: .atomic)
    }

    public func remove() throws {
        if let loadError { throw StoreError.unreadable(url, loadError) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public enum StoreError: LocalizedError {
    case unreadable(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let error):
            "\(url.lastPathComponent) couldn't be read, so it wasn't overwritten: \(error.localizedDescription)"
        }
    }
}

extension JSONEncoder {
    static var detour: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var detour: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
