import AppKit
import SwiftUI

struct ProfilesPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    @State private var selectedID: String?

    private var selectedIndex: Int? {
        store.settings.profiles.firstIndex { $0.bundleID == selectedID }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    profileList
                    Divider()
                    if let index = selectedIndex {
                        ProfileEditor(env: env, store: store, index: index)
                    } else {
                        Text("Select or add an app.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .frame(minHeight: 260)
            } header: {
                Text("App Profiles")
            } footer: {
                PaneFooter("When you bring up the island from an app with a profile, its actions appear in the capsule (set Resting state to “App actions” in General to show them first). Actions use the app's own scripting support, so macOS asks once for Automation permission per app.")
            }
        }
        .onAppear { if selectedID == nil { selectedID = store.settings.profiles.first?.bundleID } }
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: $selectedID) {
                ForEach(store.settings.profiles) { profile in
                    HStack(spacing: 8) {
                        AppIconView(bundleID: profile.bundleID).frame(width: 18, height: 18)
                        Text(profile.name)
                        Spacer()
                        if !profile.isEnabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(profile.bundleID)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(width: 210, height: 220)
            HStack(spacing: 4) {
                Menu {
                    ForEach(candidateApps, id: \.bundleID) { app in
                        Button(app.name) { addProfile(bundleID: app.bundleID, name: app.name) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a profile for a running app")
                Button {
                    guard let selectedID else { return }
                    store.settings.profiles.removeAll { $0.bundleID == selectedID }
                    self.selectedID = store.settings.profiles.first?.bundleID
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                Spacer()
                Button("Restore Defaults") {
                    store.settings.profiles = AppProfile.defaults
                    selectedID = store.settings.profiles.first?.bundleID
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var candidateApps: [(bundleID: String, name: String)] {
        let existing = Set(store.settings.profiles.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .filter { !existing.contains($0.0) && $0.0 != Bundle.main.bundleIdentifier }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            .map { (bundleID: $0.0, name: $0.1) }
    }

    private func addProfile(bundleID: String, name: String) {
        store.settings.profiles.append(AppProfile(bundleID: bundleID, name: name, isEnabled: true, actions: []))
        selectedID = bundleID
    }
}

private struct ProfileEditor: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppIconView(bundleID: store.settings.profiles[index].bundleID).frame(width: 28, height: 28)
                VStack(alignment: .leading) {
                    Text(store.settings.profiles[index].name).font(.headline)
                    Text(store.settings.profiles[index].bundleID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $store.settings.profiles[index].isEnabled).toggleStyle(.switch)
            }
            Text("Actions (left to right)").font(.subheadline).foregroundStyle(.secondary)
            List {
                ForEach(Array(store.settings.profiles[index].actions.enumerated()), id: \.offset) { offset, ref in
                    HStack {
                        let resolved = env.actions.resolve([ref]).first
                        Image(systemName: resolved?.symbol ?? "questionmark").frame(width: 20)
                        Text(resolved?.title ?? "Missing action")
                        Spacer()
                        Button {
                            store.settings.profiles[index].actions.remove(at: offset)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(resolved?.title ?? "action")")
                    }
                }
                .onMove { source, destination in
                    store.settings.profiles[index].actions.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 150)
            ActionAddMenu(store: store) { ref in store.settings.profiles[index].actions.append(ref) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Add Action" menu grouped by category, plus the user's custom shortcuts.
struct ActionAddMenu: View {
    @ObservedObject var store: SettingsStore
    let onAdd: (ActionRef) -> Void

    var body: some View {
        Menu("Add Action") {
            ForEach(BuiltInAction.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(BuiltInAction.allCases.filter { $0.category == category }) { action in
                        Button {
                            onAdd(.builtIn(action))
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                }
            }
            if !store.settings.customActions.isEmpty {
                Section("Custom") {
                    ForEach(store.settings.customActions) { custom in
                        Button {
                            onAdd(.custom(custom.id))
                        } label: {
                            Label(custom.title, systemImage: custom.symbol)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }
}

struct AppIconView: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
        }
    }
}

struct ShortcutsPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                if store.settings.customActions.isEmpty {
                    Text("No custom shortcuts yet.").foregroundStyle(.secondary)
                }
                ForEach($store.settings.customActions) { $action in
                    CustomActionRow(action: $action) {
                        let id = action.id
                        store.update { settings in
                            settings.customActions.removeAll { $0.id == id }
                            settings.dashboardActions.removeAll { $0 == .custom(id) }
                            for index in settings.profiles.indices { settings.profiles[index].actions.removeAll { $0 == .custom(id) } }
                        }
                    }
                }
                Menu("Add Shortcut") {
                    Button("Run a Shortcut…") {
                        store.settings.customActions.append(CustomAction(title: "Shortcut", symbol: "square.stack.3d.up.fill", kind: .runShortcut("")))
                    }
                    Button("Open a Link…") {
                        store.settings.customActions.append(CustomAction(title: "Link", symbol: "link", kind: .openURL("https://")))
                    }
                    Button("Open an App…") {
                        store.settings.customActions.append(CustomAction(title: "App", symbol: "app.fill", kind: .openApp("com.apple.TextEdit")))
                    }
                }
                .fixedSize()
            } header: {
                Text("Custom Shortcuts")
            } footer: {
                PaneFooter("Shortcuts run through the public shortcuts:// URL scheme. Custom shortcuts can be added to the dashboard below or to any App Profile.")
            }

            Section {
                ForEach(Array(store.settings.dashboardActions.enumerated()), id: \.offset) { offset, ref in
                    HStack {
                        let resolved = env.actions.resolve([ref]).first
                        Label(resolved?.title ?? "Missing action", systemImage: resolved?.symbol ?? "questionmark")
                        Spacer()
                        Button("Remove") { store.settings.dashboardActions.remove(at: offset) }
                            .buttonStyle(.borderless)
                    }
                }
                if store.settings.dashboardActions.count < 5 {
                    ActionAddMenu(store: store) { ref in store.settings.dashboardActions.append(ref) }
                }
            } header: {
                Text("Dashboard Buttons")
            } footer: {
                PaneFooter("Up to five extra buttons on the expanded dashboard.")
            }
        }
    }
}

private struct CustomActionRow: View {
    @Binding var action: CustomAction
    let onDelete: () -> Void

    private var valueBinding: Binding<String> {
        Binding(
            get: {
                switch action.kind {
                case .openURL(let value), .openApp(let value), .runShortcut(let value): value
                }
            },
            set: { newValue in
                switch action.kind {
                case .openURL: action.kind = .openURL(newValue)
                case .openApp: action.kind = .openApp(newValue)
                case .runShortcut: action.kind = .runShortcut(newValue)
                }
            }
        )
    }

    private var valueLabel: String {
        switch action.kind {
        case .openURL: "Link"
        case .openApp: "Bundle ID"
        case .runShortcut: "Shortcut name"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) == nil ? "questionmark.square.dashed" : action.symbol)
                .frame(width: 22)
            TextField("Title", text: $action.title).frame(width: 110)
            TextField("SF Symbol", text: $action.symbol).frame(width: 150)
            TextField(valueLabel, text: valueBinding)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(action.title)")
        }
        .textFieldStyle(.roundedBorder)
    }
}
