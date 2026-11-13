import AppKit
import Combine
import UserNotifications

/// A notification the island presents. Only events this app legitimately produces or
/// receives are shown (its own timers/battery/media/clipboard, and the `dynamictouchbar://`
/// URL scheme). Other apps' notifications are private to macOS and are never read.
struct IslandNotification: Identifiable {
    enum Source: String { case timer, battery, media, clipboard, progress, custom, system }

    struct Action {
        let title: String
        let symbol: String
        let handler: () -> Void
    }

    let id: UUID
    var source: Source
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: NSColor
    var image: NSImage?
    var duration: TimeInterval?
    var action: Action?

    init(id: UUID = UUID(), source: Source, title: String, subtitle: String? = nil, symbol: String,
         tint: NSColor = .controlAccentColor, image: NSImage? = nil, duration: TimeInterval? = nil, action: Action? = nil) {
        self.id = id
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.image = image
        self.duration = duration
        self.action = action
    }
}

/// Stores notification payloads for the views, and forwards presentation to the coordinator.
final class NotificationsModel {
    private(set) var items: [UUID: IslandNotification] = [:]
    private var order: [UUID] = []
    private let limit = 12

    /// Set by the environment: presents `.notification(id)` on the island.
    var present: ((IslandNotification, _ holdWhenHidden: Bool) -> Void)?

    func post(_ notification: IslandNotification, holdWhenHidden: Bool = true) {
        items[notification.id] = notification
        order.append(notification.id)
        while order.count > limit {
            let dropped = order.removeFirst()
            items[dropped] = nil
        }
        present?(notification, holdWhenHidden)
    }

    func notification(_ id: UUID) -> IslandNotification? { items[id] }
}

/// Mirrors important events (timer done) to Notification Center when the island isn't on
/// screen. Uses the public UserNotifications framework and asks permission first.
final class SystemNotifier {
    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.system.error("Notification authorization: \(error.localizedDescription, privacy: .public)") }
            Log.system.info("Notification authorization granted: \(granted)")
        }
    }

    func deliver(title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.system.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func authorizationStatus(_ completion: @escaping @MainActor (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in completion(status) }
        }
    }
}
