import Foundation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (macOS 13+). The system's own Login Items
/// list is the source of truth, so this is not duplicated in our settings.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
