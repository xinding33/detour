import AppKit
import DetourCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let updates = Updates()
    private var controller: Controller!
    private var statusItem: NSStatusItem!
    private let header = MenuHeaderView()
    private var settings: SettingsWindow?
    private var shownIcon: Summary.Icon?

    /// Posted by a second copy, so the running one shows Settings instead.
    static let showSettingsNotification = Notification.Name("\(bundleID).showSettings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would fight the first over Tailscale.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            Relaunch.terminate()
            return
        }

        installMainMenu()
        LoginItem.refresh()
        controller = Controller(folder: supportURL)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = appName
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        controller.onChange = { [weak self] in self?.refresh() }
        controller.start()
        updates.start()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettingsFromAnotherCopy), name: Self.showSettingsNotification,
            object: nil, suspensionBehavior: .deliverImmediately)
        if controller.isFirstLaunch { showSettings() }
        log.info("\(appName, privacy: .public) \(appVersion.description, privacy: .public) started")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Quitting waits for a running command and hands Tailscale back, except that an update
    /// restarting Detour mid-session leaves it off for the new copy to carry on.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let handBack = !Relaunch.isRelaunching
        guard let controller, controller.mustWaitBeforeQuitting(handBack: handBack) else { return .terminateNow }
        controller.shutDown(handBack: handBack) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    /// Updates the icon, and the menu's header while it's open.
    private func refresh() {
        let summary = controller.summary
        if summary.icon != shownIcon {
            shownIcon = summary.icon
            statusItem.button?.image = StatusIcon.image(summary.icon)
        }
        statusItem.button?.toolTip = "\(summary.title)\n\(summary.detail)"
        header.show(summary)
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        controller.menuIsOpen = true
        controller.poll()
    }

    func menuDidClose(_ menu: NSMenu) {
        controller.menuIsOpen = false
    }

    /// Rebuilt each time it opens. Keep it short: what Detour is doing, and Pause. Everything
    /// else is in Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let summary = controller.summary
        header.show(summary)
        let headerItem = NSMenuItem()
        headerItem.view = header
        headerItem.toolTip = summary.detail
        menu.addItem(headerItem)
        switch summary.fix {
        case .openTailscale: add("Open Tailscale", to: menu, action: #selector(openTailscale))
        case .getTailscale: add("Get Tailscale…", to: menu, action: #selector(getTailscale))
        case nil: break
        }
        menu.addItem(.separator())

        if summary.icon == .paused {
            add("Resume Detour", to: menu, action: #selector(resume))
        } else {
            let pause = add("Pause Detour", to: menu)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            add("For 1 Hour", to: submenu, action: #selector(pauseForAnHour))
            add("Until I Resume", to: submenu, action: #selector(pauseUntilResumed))
            if controller.session?.origin == .turnedOff {
                submenu.addItem(.separator())
                add("Pausing now turns Tailscale back on.", to: submenu).isEnabled = false
            }
            pause.submenu = submenu
        }
        menu.addItem(.separator())
        add("Settings…", to: menu, action: #selector(showSettings), key: ",")
        menu.addItem(.separator())
        add("Quit \(appName)", to: menu, action: #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ title: String, to menu: NSMenu, action: Selector? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        // macOS 27 adds symbols to items like Quit. The setting is in the macOS 27 SDK (Swift 6.4),
        // and CI's Xcode may be older than this Mac's.
        #if compiler(>=6.4)
        if #available(macOS 27, *) { item.preferredImageVisibility = .hidden }
        #endif
        menu.addItem(item)
        return item
    }

    @objc private func pauseForAnHour() { controller.pause(for: 60 * 60) }
    @objc private func pauseUntilResumed() { controller.pause(for: nil) }
    @objc private func resume() { controller.resume() }
    @objc private func quit() { Relaunch.terminate() }
    @objc private func getTailscale() { NSWorkspace.shared.open(TailscaleApp.downloadPage) }

    @objc private func openTailscale() {
        guard let app = TailscaleClient.appURL else { return getTailscale() }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, _ in
            // Give it a moment to start before checking again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { self?.controller.poll() } }
        }
    }

    @objc private func showSettingsFromAnotherCopy() { showSettings() }

    @objc private func showSettings() {
        if settings == nil { settings = SettingsWindow(controller: controller, updates: updates) }
        settings?.show()
    }

    /// Menu bar apps have no visible main menu, but windows still need one for ⌘C, ⌘V and ⌘W.
    private func installMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}

/// The top of the menu: what Detour is doing, on two lines. A view, so the countdown can tick
/// while the menu is open.
final class MenuHeaderView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 44))
        title.font = .menuFont(ofSize: 0)
        title.textColor = .labelColor
        detail.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        for field in [title, detail] {
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        detail.preferredMaxLayoutWidth = 262
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ summary: Summary) {
        guard title.stringValue != summary.title || detail.stringValue != summary.detail else { return }
        title.stringValue = summary.title
        detail.stringValue = summary.detail
        setFrameSize(NSSize(width: frame.width, height: fittingSize.height))
    }
}
