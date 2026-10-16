/// Games and game-streaming apps the Add Apps sheet suggests when they're installed. A wrong or
/// outdated identifier only means the app isn't suggested.
public enum KnownApps {
    public static let geForceNow = WatchedApp(bundleID: "com.nvidia.gfnpc.mall", name: "GeForce NOW")

    public static let all: [WatchedApp] = [
        geForceNow,
        WatchedApp(bundleID: "net.battle.app", name: "Battle.net"),
        WatchedApp(bundleID: "com.blizzard.worldofwarcraft", name: "World of Warcraft"),
        WatchedApp(bundleID: "com.valvesoftware.steam", name: "Steam"),
        WatchedApp(bundleID: "com.valvesoftware.SteamLink", name: "Steam Link"),
        WatchedApp(bundleID: "com.epicgames.EpicGamesLauncher", name: "Epic Games Launcher"),
        WatchedApp(bundleID: "com.moonlight-stream.Moonlight", name: "Moonlight"),
        WatchedApp(bundleID: "tv.parsec.www", name: "Parsec"),
        WatchedApp(bundleID: "com.playstation.RemotePlay", name: "PS Remote Play"),
    ]

    public static func isKnown(_ bundleID: String) -> Bool {
        all.contains { $0.bundleID == bundleID }
    }
}
