import Foundation

/// Feature modules the user can toggle.
nonisolated enum IslandModule: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case music, battery, volume, brightness, notifications, clipboard, timer, progress, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Music"
        case .battery: "Battery"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .notifications: "Notifications"
        case .clipboard: "Clipboard"
        case .timer: "Timer & Focus"
        case .progress: "Progress"
        case .shortcuts: "App Actions & Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .battery: "battery.75percent"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .notifications: "bell.badge.fill"
        case .clipboard: "doc.on.clipboard"
        case .timer: "timer"
        case .progress: "arrow.down.circle"
        case .shortcuts: "command"
        }
    }
}

/// Long-running content that can sit in the capsule (or the secondary bubble).
nonisolated enum LiveActivityKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case music, timer, progress

    var id: String { rawValue }

    var module: IslandModule {
        switch self {
        case .music: .music
        case .timer: .timer
        case .progress: .progress
        }
    }

    var title: String { module.title }
}

/// Short-lived content that temporarily takes over the capsule.
nonisolated enum TransientKind: Hashable, Sendable {
    case volume
    case brightness
    case battery
    case clipboard
    case notification(UUID)

    var module: IslandModule {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .battery: .battery
        case .clipboard: .clipboard
        case .notification: .notifications
        }
    }

    var isNotification: Bool {
        if case .notification = self { return true }
        return false
    }
}

/// What the island renders. The 10 required states map to these cases:
/// minimal, expanded (dashboard), music, notification, battery, volume, brightness,
/// timer, progress and contextual application state — plus clipboard.
nonisolated enum PresentationContent: Hashable, Sendable {
    case minimal
    case dashboard
    case music(expanded: Bool)
    case timer(expanded: Bool)
    case progress(expanded: Bool)
    case contextual
    case volume
    case brightness
    case battery
    case clipboard
    case notification(UUID)

    /// Stable identity. Same id ⇒ update in place; different id ⇒ animated transition.
    var id: String {
        switch self {
        case .minimal: "minimal"
        case .dashboard: "dashboard"
        case .music(let expanded): expanded ? "music.expanded" : "music.compact"
        case .timer(let expanded): expanded ? "timer.expanded" : "timer.compact"
        case .progress(let expanded): expanded ? "progress.expanded" : "progress.compact"
        case .contextual: "contextual"
        case .volume: "volume"
        case .brightness: "brightness"
        case .battery: "battery"
        case .clipboard: "clipboard"
        case .notification(let id): "notification.\(id.uuidString)"
        }
    }

    var isExpanded: Bool {
        switch self {
        case .minimal: false
        case .music(let expanded), .timer(let expanded), .progress(let expanded): expanded
        default: true
        }
    }

    var debugName: String { id }
}

/// Default resting state when no live activity is running.
nonisolated enum DefaultIslandState: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal, dashboard, contextual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .dashboard: "Expanded dashboard"
        case .contextual: "App actions (when available)"
        }
    }
}

/// The full output of the state machine.
nonisolated struct IslandLayoutState: Equatable, Sendable {
    var primary: PresentationContent
    /// A second live activity shown as a detached bubble.
    var secondary: LiveActivityKind?

    static let initial = IslandLayoutState(primary: .minimal, secondary: nil)
}
