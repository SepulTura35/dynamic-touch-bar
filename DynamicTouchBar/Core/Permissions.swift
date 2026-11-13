import AppKit
import Combine
import UserNotifications

nonisolated enum PermissionState: Equatable, Sendable {
    case granted, denied, notDetermined, appNotRunning, unknown

    var title: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        case .appNotRunning: "Open the app to check"
        case .unknown: "Unknown"
        }
    }
}

/// Reads permission status with public APIs only (`AEDeterminePermissionToAutomateTarget`,
/// `AXIsProcessTrusted`, `UNUserNotificationCenter`). Nothing is requested without a click.
final class PermissionsModel: ObservableObject {
    struct AutomationTarget: Identifiable, Hashable {
        let bundleID: String
        let name: String
        let reason: String
        var id: String { bundleID }
    }

    static let automationTargets: [AutomationTarget] = [
        AutomationTarget(bundleID: "com.apple.Music", name: "Music", reason: "Track info, artwork and playback controls"),
        AutomationTarget(bundleID: "com.spotify.client", name: "Spotify", reason: "Track info, artwork and playback controls"),
        AutomationTarget(bundleID: "com.apple.dt.Xcode", name: "Xcode", reason: "Build, Run, Test, Stop and Clean actions"),
        AutomationTarget(bundleID: "com.apple.Safari", name: "Safari", reason: "New Tab, Reload and Copy URL actions"),
        AutomationTarget(bundleID: "com.apple.finder", name: "Finder", reason: "New Window and Copy Path actions"),
    ]

    @Published private(set) var automation: [String: PermissionState] = [:]
    @Published private(set) var accessibility = false
    @Published private(set) var notifications: PermissionState = .unknown

    func refresh() {
        accessibility = KeyEventPoster.isTrusted
        SystemNotifier.authorizationStatus { [weak self] status in
            self?.notifications = switch status {
            case .authorized, .provisional: .granted
            case .denied: .denied
            case .notDetermined: .notDetermined
            default: .unknown
            }
        }
        for target in Self.automationTargets {
            Self.automationStatus(bundleID: target.bundleID, ask: false) { [weak self] state in
                self?.automation[target.bundleID] = state
            }
        }
    }

    func requestAutomation(_ bundleID: String) {
        Self.automationStatus(bundleID: bundleID, ask: true) { [weak self] state in
            self?.automation[bundleID] = state
        }
    }

    nonisolated static func automationStatus(bundleID: String, ask: Bool, completion: @escaping @MainActor @Sendable (PermissionState) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            let state: PermissionState = switch Int(status) {
            case Int(noErr): .granted
            case -1743: .denied
            case -1744: .notDetermined
            case -600: .appNotRunning
            default: .unknown
            }
            Task { @MainActor in completion(state) }
        }
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
