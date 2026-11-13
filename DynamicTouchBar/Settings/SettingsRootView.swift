import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, modules, profiles, shortcuts, permissions, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .modules: "Modules"
        case .profiles: "App Profiles"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .modules: "square.grid.2x2.fill"
        case .profiles: "app.badge.fill"
        case .shortcuts: "command"
        case .permissions: "lock.shield.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .pink
        case .modules: .blue
        case .profiles: .indigo
        case .shortcuts: .orange
        case .permissions: .green
        case .advanced: .purple
        case .about: .secondary
        }
    }
}

struct SettingsRootView: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            VStack(spacing: 0) {
                IslandPreviewHeader(env: env, store: store)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                Divider().opacity(0.4)
                Group {
                    switch selection ?? .general {
                    case .general: GeneralPane(env: env, store: store)
                    case .appearance: AppearancePane(env: env, store: store)
                    case .modules: ModulesPane(env: env, store: store)
                    case .profiles: ProfilesPane(env: env, store: store)
                    case .shortcuts: ShortcutsPane(env: env, store: store)
                    case .permissions: PermissionsPane(env: env, store: store)
                    case .advanced: AdvancedPane(env: env, store: store)
                    case .about: AboutPane(env: env)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(selection?.title ?? "DynamicTouchBar")
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// Live preview using the exact renderer that drives the physical Touch Bar.
struct IslandPreviewHeader: View {
    let env: AppEnvironment
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                IslandPreview(env: env)
                    .frame(width: IslandMetrics.defaultAppRegionWidth, height: IslandMetrics.barHeight)
            }
            .frame(width: IslandMetrics.defaultAppRegionWidth + 16, height: IslandMetrics.barHeight + 16)
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Image(systemName: env.hardware.hasTouchBar ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(env.hardware.hasTouchBar ? .green : .orange)
                Text(env.hardware.hasTouchBar
                     ? "Live preview — mirrored on your Touch Bar while this window is open."
                     : "Preview only — this Mac has no physical Touch Bar.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Tap Island") { env.coordinator.tapCapsule() }
                    .controlSize(.small)
            }
            .font(.callout)
        }
    }
}

struct IslandPreview: NSViewRepresentable {
    let env: AppEnvironment

    func makeNSView(context: Context) -> IslandView {
        IslandView(env: env, role: .preview)
    }

    func updateNSView(_ nsView: IslandView, context: Context) {}
}

/// Small helper for explanatory footers.
struct PaneFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
