import AppKit
import DetourCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let updates = Updates()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would fight the first over the menu bar and whatever the app controls.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            others.first?.activate()
            Relaunch.terminate()
            return
        }

        installMainMenu()
        LoginItem.refresh()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: appName)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = appName
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updates.start()
        log.info("\(appName, privacy: .public) \(appVersion.description, privacy: .public) started")
    }

    // MARK: Menu

    /// Rebuilt each time it opens, so it always shows the current state. Keep it short: what's
    /// done in a hurry. Once there's a Settings window, settings go there, not here as well.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // The app's own items go here, followed by a separator.
        let login = add("Open at Login", to: menu, action: #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        if let problem = LoginItem.problem { login.isEnabled = false; login.toolTip = problem }
        if LoginItem.needsApproval {
            add("Allow in Login Items Settings…", to: menu, action: #selector(openLoginItemsSettings))
        }
        add("Check for Updates…", to: menu, action: #selector(checkForUpdates))
        let automatic = add("Install Updates Automatically", to: menu, action: #selector(toggleAutomaticUpdates))
        automatic.state = updates.automatic && updates.canInstall ? .on : .off
        automatic.isEnabled = updates.canInstall
        if !updates.canInstall { automatic.toolTip = "Only copies installed from a release can update themselves." }
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

    @objc private func toggleLogin() {
        do { try LoginItem.setEnabled(!LoginItem.isEnabled) } catch { show(error, "Couldn't change Open at Login") }
    }

    @objc private func openLoginItemsSettings() { NSWorkspace.shared.open(LoginItem.settingsURL) }
    @objc private func checkForUpdates() { updates.checkNow() }
    @objc private func toggleAutomaticUpdates() { updates.automatic.toggle() }
    @objc private func quit() { Relaunch.terminate() }

    private func show(_ error: Error, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
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
