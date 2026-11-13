import AppKit
import Combine

struct AppIdentity: Equatable {
    let bundleID: String
    let name: String
    let processIdentifier: pid_t

    var icon: NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSRunningApplication(processIdentifier: processIdentifier)?.icon
    }

    var runningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }
}

/// Tracks the app the user was working in, via the public
/// `NSWorkspace.didActivateApplicationNotification`. Because the island is only on the Touch
/// Bar while DynamicTouchBar is active, the *context* is the last app that was active before
/// that — the one the user summoned the island from.
final class ContextMonitor: ObservableObject {
    @Published var contextApp: AppIdentity?

    private var observer: NSObjectProtocol?
    private let ownBundleID = Bundle.main.bundleIdentifier

    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication { consider(front) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app { self?.consider(app) }
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func consider(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID else { return }
        let identity = AppIdentity(bundleID: bundleID, name: app.localizedName ?? bundleID, processIdentifier: app.processIdentifier)
        if identity != contextApp { contextApp = identity }
    }
}
