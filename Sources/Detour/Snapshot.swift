import AppKit
import SwiftUI
import DetourCore

/// `Detour --snapshot DIR` renders the menu bar icons, the menu's header and the Settings window
/// to PNGs in light and dark, so the UI can be reviewed without looking at the screen. It reads
/// no settings and never touches Tailscale.
@MainActor
enum Snapshot {
    static func run(to folder: URL) -> Never {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("DetourSnapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let gfn = KnownApps.geForceNow
        let battleNet = WatchedApp(bundleID: "net.battle.app", name: "Battle.net")
        let start = Date().addingTimeInterval(-15 * 60)
        let headers: [(String, Summary.Inputs)] = [
            ("watching", .init(session: nil, configured: [gfn, battleNet], tailscale: .on, now: Date(), time: time)),
            ("detouring", .init(session: Session(origin: .turnedOff, started: start, apps: ["GeForce NOW"]),
                                configured: [gfn], tailscale: .off, now: Date(), time: time)),
            ("grace", .init(session: Session(origin: .turnedOff, started: start, apps: ["GeForce NOW"],
                                             lastQuit: Date().addingTimeInterval(-3)),
                            configured: [gfn], tailscale: .off, now: Date(), time: time)),
            ("override", .init(session: Session(origin: .userTurnedOn, started: start, apps: ["GeForce NOW"]),
                               configured: [gfn], tailscale: .on, now: Date(), time: time)),
            ("paused", .init(session: nil, configured: [gfn], tailscale: .on,
                             pause: .until(Date().addingTimeInterval(3600)), now: Date(), time: time)),
            ("problem", .init(session: nil, configured: [gfn], tailscale: .unreachable("Tailscale isn't running."),
                              now: Date(), time: time)),
        ]

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let look = NSAppearance(named: appearance)!
            for icon in [Summary.Icon.watching, .detouring, .paused, .problem] {
                let view = IconSample(icon: icon)
                write(view, look, folder.appendingPathComponent("icon-\(icon)-\(name).png"))
            }
            for (label, inputs) in headers {
                let header = MenuHeaderView()
                header.show(Summary.make(inputs))
                let box = NSView(frame: header.frame)
                box.wantsLayer = true
                box.layer?.backgroundColor = (appearance == .aqua ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.17, alpha: 1)).cgColor
                box.addSubview(header)
                write(box, look, folder.appendingPathComponent("header-\(label)-\(name).png"))
            }
            let controller = Controller(folder: scratch, isPreview: true)
            controller.configuration = Configuration(apps: [gfn, battleNet])
            controller.preview(tailscale: TailscaleStatus(state: .on, version: "1.104.1"), running: [gfn.bundleID])
            write(NSHostingView(rootView: SettingsView(controller: controller, updates: Updates())
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)),
                  look, folder.appendingPathComponent("settings-\(name).png"))
            write(NSHostingView(rootView: AddAppsView(existing: [gfn.bundleID]) { _ in }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)),
                  look, folder.appendingPathComponent("add-apps-\(name).png"))
        }
        print("Wrote snapshots to \(folder.path)")
        exit(0)
    }

    private static let time: @Sendable (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }

    /// Puts `view` in an offscreen window so it lays out, then saves it at 2x.
    private static func write(_ view: NSView, _ appearance: NSAppearance, _ url: URL) {
        let fixed = view.frame.size
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize.width > 0 && view.fittingSize.height > 0 ? view.fittingSize : fixed
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        appearance.performAsCurrentDrawingAppearance {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

/// An icon on a menu bar colored background, tinted the way macOS tints template images.
private final class IconSample: NSView {
    let icon: Summary.Icon

    init(icon: Summary.Icon) {
        self.icon = icon
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 26))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        bounds.fill()
        let image = StatusIcon.image(icon)
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            (dark ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: 8, y: 4, width: 18, height: 18))
    }
}
