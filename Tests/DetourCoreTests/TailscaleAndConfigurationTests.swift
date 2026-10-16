import Foundation
import Testing
@testable import DetourCore

@Suite struct TailscaleStatusTests {
    private func parse(_ json: String, exit: Int32 = 0, error: String = "") -> TailscaleStatus {
        TailscaleStatus.parse(output: Data(json.utf8), exitStatus: exit, errorOutput: error)
    }

    @Test func backendStates() {
        #expect(parse(#"{"BackendState":"Running","Version":"1.104.1-t7f4efe814-g4939ea2e4"}"#)
            == TailscaleStatus(state: .on, version: "1.104.1"))
        #expect(parse(#"{"BackendState":"Starting"}"#).state == .on)
        #expect(parse(#"{"BackendState":"Stopped"}"#, exit: 1).state == .off)
        #expect(parse(#"{"BackendState":"NeedsLogin"}"#).state == .needsLogin)
        #expect(parse(#"{"BackendState":"NeedsMachineAuth"}"#).state == .needsLogin)
        #expect(parse(#"{"BackendState":"NoState"}"#).state.isControllable == false)
    }

    @Test func failures() {
        let notRunning = parse("", exit: 1,
                               error: "failed to connect to local Tailscale service; is Tailscale running?\n")
        #expect(notRunning.state == .unreachable("Tailscale isn't running."))
        #expect(parse("", exit: 2).state == .unreachable("The Tailscale CLI failed (exit status 2)."))
        #expect(parse("nope", exit: 1, error: "first line\nusage").state == .unreachable("first line"))
    }
}

@Suite struct ConfigurationTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DetourTests-\(UUID().uuidString)/config.json")
    }

    @Test func addKeepsOrderAndSkipsDuplicates() {
        var config = Configuration(apps: [KnownApps.geForceNow])
        config.add([WatchedApp(bundleID: "b", name: "B"), KnownApps.geForceNow, WatchedApp(bundleID: "a", name: "A")])
        #expect(config.apps.map(\.bundleID) == ["com.nvidia.gfnpc.mall", "b", "a"])
        config.remove(bundleIDs: ["b"])
        #expect(config.apps.map(\.bundleID) == ["com.nvidia.gfnpc.mall", "a"])
        #expect(config.watched(running: ["a", "x"]).map(\.name) == ["A"])
    }

    @Test func roundTrips() throws {
        let store = JSONStore<Configuration>(url: temporaryURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        #expect(store.load() == nil)
        let config = Configuration(apps: [KnownApps.geForceNow], graceSeconds: 25)
        try store.save(config)
        #expect(JSONStore<Configuration>(url: store.url).load() == config)
    }

    @Test func missingKeysGetDefaults() throws {
        let config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        #expect(config == Configuration())
    }

    @Test func refusesToOverwriteAFileItCouldNotRead() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = JSONStore<Configuration>(url: url)
        #expect(store.load() == nil)
        #expect(throws: StoreError.self) { try store.save(Configuration()) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func sessionsRoundTrip() throws {
        let store = JSONStore<Session>(url: temporaryURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let session = Session(origin: .turnedOff, started: Date(timeIntervalSince1970: 1_800_000_000),
                              apps: ["GeForce NOW"], lastQuit: Date(timeIntervalSince1970: 1_800_000_100))
        try store.save(session)
        #expect(store.load() == session)
        try store.remove()
        #expect(store.load() == nil)
    }
}
