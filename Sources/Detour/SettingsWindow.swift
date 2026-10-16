import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DetourCore

/// The Settings window: one pane, no tabs.
@MainActor
final class SettingsWindow {
    private let window: NSWindow

    init(controller: Controller, updates: Updates) {
        let hosting = NSHostingController(rootView: SettingsView(controller: controller, updates: updates))
        hosting.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: hosting)
        window.title = appName
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var controller: Controller
    @Bindable var updates: Updates
    @State private var selection: Set<String> = []
    @State private var addingApps = false
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                if controller.configuration.apps.isEmpty {
                    Text("No apps yet. Add one with +.")
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.configuration.apps) { app in
                    AppRow(app: app, isOpen: controller.running.contains(app.bundleID))
                        .contentShape(Rectangle())
                        .onTapGesture { toggleSelection(app.bundleID) }
                        .listRowBackground(selection.contains(app.bundleID) ? Color.accentColor.opacity(0.18) : nil)
                }
                HStack(spacing: 0) {
                    Button { addingApps = true } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                        .help("Add apps")
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                        .disabled(selection.isEmpty)
                        .help("Remove the selected apps")
                    Spacer()
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Turn Tailscale off while any of these apps is open")
            } footer: {
                Text("Tailscale turns back on once every app in this list has quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Stepper(value: $controller.configuration.graceSeconds, in: Configuration.graceRange, step: 5) {
                    LabeledContent("Wait before turning Tailscale back on") {
                        Text(controller.configuration.graceSeconds == 1 ? "1 second" : "\(controller.configuration.graceSeconds) seconds")
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Reconnecting")
            } footer: {
                Text("Stops Tailscale flapping when an app restarts. Detour only turns Tailscale back on if Detour turned it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("General") {
                LabeledContent {
                    if controller.tailscale.state == .notInstalled {
                        Button("Get Tailscale…") { NSWorkspace.shared.open(TailscaleApp.downloadPage) }
                    } else {
                        Button("Open Tailscale") { openTailscale() }
                    }
                } label: {
                    Text("Tailscale")
                    Text(tailscaleDescription)
                }
                // Bound by key path, not a `Binding(get:set:)`: a `(Bool) -> ()` closure there
                // crashes Swift 6.3's IR generation (CI's Xcode 26.6).
                Toggle(isOn: $openAtLogin) {
                    Text("Open at Login")
                    if let problem = LoginItem.problem ?? loginError { Text(problem) }
                }
                .disabled(LoginItem.problem != nil)
                .onChange(of: openAtLogin) { _, enabled in setOpenAtLogin(enabled) }
                if LoginItem.needsApproval {
                    Button("Allow in Login Items Settings…") { NSWorkspace.shared.open(LoginItem.settingsURL) }
                }
                LabeledContent {
                    Button("Check for Updates") { updates.checkNow() }
                        .disabled(updates.status != nil)
                } label: {
                    Text("\(appName) \(appVersion.description)")
                    Text(updateDescription)
                }
                Toggle(isOn: $updates.automatic) {
                    Text("Install updates automatically")
                    if !updates.canInstall { Text("Only copies installed from a release can update themselves.") }
                }
                .disabled(!updates.canInstall)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $addingApps) {
            AddAppsView(existing: Set(controller.configuration.apps.map(\.bundleID))) { apps in
                controller.configuration.add(apps)
            }
        }
        .onAppear { controller.poll() }
    }

    private var tailscaleDescription: String {
        let state = switch controller.tailscale.state {
        case .unknown: "Checking…"
        case .on: "Connected"
        case .off: "Off"
        case .needsLogin: "Logged out"
        case .notInstalled: "The standalone app isn't installed"
        case .unreachable: "Not running"
        }
        return ([controller.tailscale.version, controller.tailscale.state == .notInstalled ? nil : "Standalone", state]
            .compactMap { $0 }).joined(separator: " · ")
    }

    private var updateDescription: String {
        if let status = updates.status { return status }
        guard updates.lastCheck != .distantPast else { return "Not checked yet" }
        let checked = "checked \(updates.lastCheck.formatted(.relative(presentation: .named)))"
        if let latest = updates.latest, latest > appVersion { return "\(latest) is available · \(checked)" }
        return "Up to date · \(checked)"
    }

    private func toggleSelection(_ bundleID: String) {
        if selection.contains(bundleID) { selection.remove(bundleID) } else { selection.insert(bundleID) }
    }

    private func remove() {
        controller.configuration.remove(bundleIDs: selection)
        selection = []
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        openAtLogin = LoginItem.isEnabled
    }

    private func openTailscale() {
        guard let app = TailscaleClient.appURL else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// An app in the list: icon, name, bundle identifier, and whether it's open.
private struct AppRow: View {
    let app: WatchedApp
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfo.icon(for: app.bundleID))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(isOpen ? "Open" : "Not open")
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(isOpen ? Color.green : Color.secondary)
                .background(Capsule().fill(isOpen ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12)))
        }
    }
}

enum AppInfo {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    @MainActor
    static func icon(for bundleID: String) -> NSImage {
        if let url = url(for: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .application)
    }

    /// The app's name as Finder shows it, without ".app".
    static func name(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Suggests installed games and streaming apps, and apps that are open now.
struct AddAppsView: View {
    let existing: Set<String>
    let onAdd: ([WatchedApp]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var checked: Set<String> = []
    @State private var suggested: [WatchedApp] = []
    @State private var openNow: [WatchedApp] = []
    @State private var chosen: [WatchedApp] = []
    @State private var choosing = false
    @State private var chooseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Apps").font(.headline)
                Text("Tailscale turns off while any checked app is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                section("Games and streaming on this Mac", suggested)
                section("Open now", openNow)
                section("Chosen", chosen)
                if filtered(suggested).isEmpty && filtered(openNow).isEmpty && filtered(chosen).isEmpty {
                    Text(search.isEmpty ? "Nothing to suggest. Choose an app instead." : "No matches.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered)
            .frame(height: 320)
            if let chooseError {
                Text(chooseError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Choose Another App…") { choosing = true }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(checked.count == 1 ? "Add 1 App" : "Add \(checked.count) Apps") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(checked.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear(perform: load)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result { choose(url) }
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications"))
    }

    @ViewBuilder
    private func section(_ title: String, _ apps: [WatchedApp]) -> some View {
        let shown = filtered(apps)
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown) { app in
                    let added = existing.contains(app.bundleID)
                    Toggle(isOn: added ? .constant(true) : $checked[contains: app.bundleID]) {
                        HStack(spacing: 8) {
                            Image(nsImage: AppInfo.icon(for: app.bundleID))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                            if added { Text("· already added").foregroundStyle(.secondary) }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(added)
                }
            }
        }
    }

    private func filtered(_ apps: [WatchedApp]) -> [WatchedApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    private func load() {
        suggested = KnownApps.all.compactMap { known in
            AppInfo.url(for: known.bundleID).map { WatchedApp(bundleID: known.bundleID, name: AppInfo.name(at: $0)) }
        }
        let skip = Set(suggested.map(\.bundleID)).union([bundleID, TailscaleApp.bundleID])
        var seen = Set<String>()
        openNow = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> WatchedApp? in
                guard let id = app.bundleIdentifier, !skip.contains(id), seen.insert(id).inserted else { return nil }
                let name = app.bundleURL.map(AppInfo.name(at:)) ?? app.localizedName ?? id
                return WatchedApp(bundleID: id, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func choose(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            chooseError = "\(AppInfo.name(at: url)) has no bundle identifier, so Detour can't recognize it."
            return
        }
        chooseError = nil
        if !(suggested + openNow + chosen).contains(where: { $0.bundleID == id }) {
            chosen.append(WatchedApp(bundleID: id, name: AppInfo.name(at: url)))
        }
        if !existing.contains(id) { checked.insert(id) }
    }

    private func add() {
        let all = suggested + openNow + chosen
        onAdd(all.filter { checked.contains($0.bundleID) })
        dismiss()
    }
}

extension Set {
    /// Whether `element` is in the set, as something a Toggle can bind to by key path.
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set { if newValue { insert(element) } else { remove(element) } }
    }
}
