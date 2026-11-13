import Combine
import Foundation

/// Owns `AppSettings`, persists every change to `UserDefaults`, and publishes updates to both
/// SwiftUI (via `ObservableObject`) and AppKit subscribers (via `$settings`).
final class SettingsStore: ObservableObject {
    static let defaultsKey = "DynamicTouchBar.Settings.v1"

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = SettingsStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
        self.settings = Self.load(from: defaults, key: key)
    }

    static func load(from defaults: UserDefaults, key: String) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.settings.error("Settings were unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            Log.settings.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restores every preference to its default (onboarding stays completed).
    func reset() {
        var fresh = AppSettings()
        fresh.hasCompletedOnboarding = settings.hasCompletedOnboarding
        settings = fresh
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
    }
}
