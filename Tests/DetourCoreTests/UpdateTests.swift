import Foundation
import Testing
@testable import DetourCore

/// Each test gets its own folder of throwaway apps, signed ad hoc with an explicit designated
/// requirement so they can stand in for releases.
@Suite final class UpdateTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    func makeApp(in name: String, identifier: String = "test.detour", version: String, build: String = "release",
                 minimumSystem: String = "14.0") throws -> URL {
        let app = folder.appendingPathComponent(name).appendingPathComponent("Detour.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Detour").path)
        let info: NSDictionary = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Detour",
                                  "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
                                  "DetourBuild": build, "LSMinimumSystemVersion": minimumSystem]
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", "--force", "--sign", "-", "-r=designated => identifier \"\(identifier)\"", app.path)
        return app
    }

    /// Zips `app` the way scripts/release.sh does.
    func zip(_ app: URL) throws -> URL {
        let zip = app.deletingLastPathComponent().appendingPathComponent("Detour.zip")
        try run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zip.path)
        return zip
    }

    func run(_ path: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(path) \(arguments)")
    }

    func installedVersion(_ app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    @Test func comparesVersionsNumerically() throws {
        #expect(try #require(Version("1.9.0")) < #require(Version("1.10.0")))
        #expect(try #require(Version("1.1.0")) < #require(Version("v1.1.1")))
        #expect(Version(parts: [27, 0, 1]) > Version("26.4")!)
        #expect(Version("v1.1") == Version("1.1.0"))
        #expect(Version("v1.1.0")?.description == "1.1.0")
        #expect(Version("1.1.0-beta") == nil)
        #expect(Version("") == nil)
    }

    @Test func findsTheDownloadInTheLatestRelease() throws {
        let json = """
            {"tag_name": "v1.2.0", "html_url": "https://github.com/xinding33/detour/releases/tag/v1.2.0",
             "assets": [
               {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
               {"name": "Detour-1.2.0.zip",
                "browser_download_url": "https://github.com/xinding33/detour/releases/download/v1.2.0/Detour-1.2.0.zip"}]}
            """
        let release = try Release(gitHubJSON: Data(json.utf8))
        #expect(release.version == Version("1.2.0"))
        #expect(release.page.absoluteString == "https://github.com/xinding33/detour/releases/tag/v1.2.0")
        #expect(release.download.lastPathComponent == "Detour-1.2.0.zip")
        let noZip = #"{"tag_name": "v1.2.0", "html_url": "https://example.com", "assets": []}"#
        #expect(throws: UpdateError.noDownload) { try Release(gitHubJSON: Data(noZip.utf8)) }
    }

    @Test func installsAnUpdateSignedLikeTheApp() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.2.0"))
        try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        #expect(installedVersion(app) == "1.2.0")
    }

    @Test func rejectsAnUpdateSignedDifferently() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", identifier: "test.impostor", version: "1.2.0"))
        #expect(throws: UpdateError.badSignature) {
            try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func rejectsAnUpdateThatIsTheWrongVersion() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.0.0"))
        #expect(throws: UpdateError.wrongVersion) {
            try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func rejectsADevelopmentBuild() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.2.0", build: "development"))
        #expect(throws: UpdateError.notARelease) {
            try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func rejectsAnUpdateForANewerMacOS() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.2.0", minimumSystem: "99.0"))
        #expect(throws: UpdateError.needsNewerMacOS("99.0")) {
            try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func neverReplacesADevelopmentBuild() throws {
        let app = try makeApp(in: "installed", version: "1.1.0", build: "development")
        let update = try zip(makeApp(in: "update", version: "1.2.0"))
        #expect(throws: UpdateError.notInstalledFromRelease) {
            try Updater.install(zip: update, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func rejectsAModifiedUpdate() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try makeApp(in: "update", version: "1.2.0")
        try Data("tampered".utf8).write(to: update.appendingPathComponent("Contents/MacOS/Detour"))
        let tampered = try zip(update)
        #expect(throws: UpdateError.badSignature) {
            try Updater.install(zip: tampered, version: #require(Version("1.2.0")), replacing: app)
        }
        #expect(installedVersion(app) == "1.1.0")
    }

    @Test func onlyDeveloperIDReleasesInstallUpdates() throws {
        let adHoc = try makeApp(in: "installed", version: "1.1.0")
        #expect(Updater.isRelease(adHoc))
        #expect(!Updater.isDeveloperIDSigned(adHoc))
        #expect(!Updater.canInstallUpdates(into: adHoc))
        #expect(!Updater.isRelease(try makeApp(in: "local", version: "1.1.0", build: "development")))
    }
}
