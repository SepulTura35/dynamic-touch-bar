import SwiftUI

struct PermissionsPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    @StateObject private var permissions = PermissionsModel()

    var body: some View {
        Form {
            Section {
                ForEach(PermissionsModel.automationTargets) { target in
                    let state = permissions.automation[target.bundleID] ?? .unknown
                    HStack {
                        AppIconView(bundleID: target.bundleID).frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.name)
                            Text(target.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(state: state)
                        if state == .notDetermined {
                            Button("Request") { permissions.requestAutomation(target.bundleID) }
                        }
                    }
                }
                Button("Open Automation Settings") { PermissionsModel.openPrivacyPane("Privacy_Automation") }
            } header: {
                Text("Automation")
            } footer: {
                PaneFooter("Used only to read what's playing and to perform actions you tap. Nothing is sent anywhere.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Accessibility")
                        Text("Brightness buttons and media keys for other players").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(state: permissions.accessibility ? .granted : .notDetermined)
                    if !permissions.accessibility {
                        Button("Allow…") { KeyEventPoster.requestTrust() }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notifications")
                        Text("Timer alerts while the island isn't showing").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(state: permissions.notifications)
                    if permissions.notifications == .notDetermined {
                        Button("Request") { env.systemNotifier.requestAuthorizationIfNeeded() }
                    }
                }
            } header: {
                Text("System")
            } footer: {
                PaneFooter("The global shortcut uses the Carbon hot-key API and needs no permission. Volume and battery use public CoreAudio and IOKit APIs and need none either.")
            }
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
}

private struct StatusBadge: View {
    let state: PermissionState

    private var color: Color {
        switch state {
        case .granted: .green
        case .denied: .red
        case .notDetermined: .orange
        default: .secondary
        }
    }

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct AdvancedPane: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(store.settings.livePriority) { kind in
                        Label(kind.title, systemImage: kind.module.symbol)
                    }
                    .onMove { source, destination in
                        store.settings.livePriority.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .frame(height: 100)
            } header: {
                Text("Module priority")
            } footer: {
                PaneFooter("Drag to reorder. When several live activities run, the first takes the capsule and the next appears as a bubble — tap the bubble to swap.")
            }

            Section {
                LabeledContent("Response") {
                    HStack {
                        Slider(value: $store.settings.customSpring.response, in: 0.15...1.2)
                        Text("\(store.settings.customSpring.response, specifier: "%.2f") s").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Damping") {
                    HStack {
                        Slider(value: $store.settings.customSpring.dampingFraction, in: 0.4...1.2)
                        Text("\(store.settings.customSpring.dampingFraction, specifier: "%.2f")").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Text("Settles in about \(SpringSolver.settlingDuration(store.settings.customSpring.scaled(speed: store.settings.animationSpeed)), specifier: "%.2f") s")
                    .font(.caption).foregroundStyle(.secondary)
                if store.settings.animationStyle != .custom {
                    Button("Use Custom Timing") { store.settings.animationStyle = .custom }
                }
            } header: {
                Text("Animation timing")
            }

            Section {
                Toggle("Debug mode", isOn: $store.settings.debugMode)
                HStack {
                    Button("Test Notification") {
                        env.notifications.post(IslandNotification(source: .custom, title: "Hello from DynamicTouchBar",
                                                                  subtitle: "This is a test notification", symbol: "sparkles", tint: .systemPurple))
                    }
                    Button("Show Battery") { env.coordinator.present(.battery) }
                    Button("Show Brightness") { env.coordinator.present(.brightness) }
                    Button("Demo Progress") { runProgressDemo() }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                PaneFooter("Debug mode prints the current island state on the capsule and logs transitions (Console ▸ subsystem com.dynamictouchbar.app). The test buttons are labelled as tests and never show fabricated system data.")
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset all DynamicTouchBar settings?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { store.reset() }
                    }
            }
        }
    }

    private func runProgressDemo() {
        let id = "demo-\(UUID().uuidString.prefix(4))"
        let progress = env.progress
        progress.upsert(id: id, title: "Demo task", fraction: 0, detail: "Test progress", symbol: "sparkles")
        for step in 1...10 {
            MainScheduler.shared.schedule(after: Double(step) * 0.6) {
                if step == 10 {
                    progress.finish(id: id, success: true, detail: "Demo finished")
                } else {
                    progress.upsert(id: id, title: nil, fraction: Double(step) / 10)
                }
            }
        }
    }
}

struct AboutPane: View {
    let env: AppEnvironment

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Mac", value: env.hardware.marketingName ?? env.hardware.modelIdentifier)
                LabeledContent("Touch Bar", value: env.hardware.hasTouchBar ? "Detected" : "Not detected")
            }
            Section("How it works") {
                Text("DynamicTouchBar uses only public macOS APIs. The Touch Bar shows the controls of the app in front, so the island appears when you bring DynamicTouchBar forward and hands control back when you're done. It never injects code into other apps or reads their private data.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Integrations") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send events from scripts, Xcode Behaviors or Shortcuts:").foregroundStyle(.secondary)
                    Group {
                        Text("open -g \"dynamictouchbar://notify?title=Deployed&symbol=checkmark.seal.fill\"")
                        Text("open -g \"dynamictouchbar://progress?id=build&title=Building&value=0.4\"")
                        Text("open -g \"dynamictouchbar://progress?id=build&state=done\"")
                        Text("open -g \"dynamictouchbar://timer?minutes=25&label=Tea\"")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
            }
            Section("Limitations") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• The island is on the Touch Bar only while DynamicTouchBar is the active app.")
                    Text("• Display brightness can be stepped but not read on Apple Silicon.")
                    Text("• Now Playing details are available for Music and Spotify only.")
                    Text("• Other apps' notifications and download percentages are not available.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}
