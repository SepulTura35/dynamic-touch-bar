import Foundation

/// Built-in actions. Each one is implemented with a public, permission-respecting mechanism
/// (an app's own AppleScript dictionary, `NSWorkspace`, or URL schemes) — never by injecting
/// into or remote-controlling another app's UI.
nonisolated enum BuiltInAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    // Media
    case mediaPlayPause, mediaNext, mediaPrevious
    // Xcode (Xcode's scripting dictionary)
    case xcodeBuild, xcodeRun, xcodeTest, xcodeStop, xcodeClean
    // Safari (Safari's scripting dictionary)
    case safariNewTab, safariReload, safariCopyURL
    // Finder
    case finderNewWindow, finderHome, finderDownloads, finderDesktop, finderApplications, finderCopyPath
    // Island
    case startPomodoro, startTimer5, startTimer15, startStopwatch, toggleMute, openScreenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mediaPlayPause: "Play/Pause"
        case .mediaNext: "Next"
        case .mediaPrevious: "Previous"
        case .xcodeBuild: "Build"
        case .xcodeRun: "Run"
        case .xcodeTest: "Test"
        case .xcodeStop: "Stop"
        case .xcodeClean: "Clean"
        case .safariNewTab: "New Tab"
        case .safariReload: "Reload"
        case .safariCopyURL: "Copy URL"
        case .finderNewWindow: "New Window"
        case .finderHome: "Home"
        case .finderDownloads: "Downloads"
        case .finderDesktop: "Desktop"
        case .finderApplications: "Apps"
        case .finderCopyPath: "Copy Path"
        case .startPomodoro: "Pomodoro"
        case .startTimer5: "5 min"
        case .startTimer15: "15 min"
        case .startStopwatch: "Stopwatch"
        case .toggleMute: "Mute"
        case .openScreenshot: "Screenshot"
        }
    }

    var symbol: String {
        switch self {
        case .mediaPlayPause: "playpause.fill"
        case .mediaNext: "forward.fill"
        case .mediaPrevious: "backward.fill"
        case .xcodeBuild: "hammer.fill"
        case .xcodeRun: "play.fill"
        case .xcodeTest: "checkmark.diamond.fill"
        case .xcodeStop: "stop.fill"
        case .xcodeClean: "trash"
        case .safariNewTab: "plus.square.on.square"
        case .safariReload: "arrow.clockwise"
        case .safariCopyURL: "link"
        case .finderNewWindow: "macwindow.badge.plus"
        case .finderHome: "house.fill"
        case .finderDownloads: "arrow.down.circle.fill"
        case .finderDesktop: "menubar.dock.rectangle"
        case .finderApplications: "square.grid.3x3.fill"
        case .finderCopyPath: "doc.on.doc"
        case .startPomodoro: "leaf.fill"
        case .startTimer5, .startTimer15: "timer"
        case .startStopwatch: "stopwatch.fill"
        case .toggleMute: "speaker.slash.fill"
        case .openScreenshot: "camera.viewfinder"
        }
    }

    /// App whose scripting dictionary this action uses (needs Automation permission).
    var automationTarget: String? {
        switch self {
        case .xcodeBuild, .xcodeRun, .xcodeTest, .xcodeStop, .xcodeClean: "com.apple.dt.Xcode"
        case .safariNewTab, .safariReload, .safariCopyURL: "com.apple.Safari"
        case .finderNewWindow, .finderCopyPath: "com.apple.finder"
        default: nil
        }
    }

    enum Category: String, CaseIterable { case media = "Media", xcode = "Xcode", safari = "Safari", finder = "Finder", island = "Island" }

    var category: Category {
        switch self {
        case .mediaPlayPause, .mediaNext, .mediaPrevious: .media
        case .xcodeBuild, .xcodeRun, .xcodeTest, .xcodeStop, .xcodeClean: .xcode
        case .safariNewTab, .safariReload, .safariCopyURL: .safari
        case .finderNewWindow, .finderHome, .finderDownloads, .finderDesktop, .finderApplications, .finderCopyPath: .finder
        case .startPomodoro, .startTimer5, .startTimer15, .startStopwatch, .toggleMute, .openScreenshot: .island
        }
    }
}

/// A user-defined button.
nonisolated struct CustomAction: Codable, Identifiable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        /// Opens any URL (web, `x-apple.systempreferences:`, app schemes…).
        case openURL(String)
        /// Launches / focuses an app by bundle identifier.
        case openApp(String)
        /// Runs a Shortcuts shortcut by name via the public `shortcuts://` URL scheme.
        case runShortcut(String)
    }

    var id: UUID
    var title: String
    var symbol: String
    var kind: Kind

    init(id: UUID = UUID(), title: String, symbol: String, kind: Kind) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.kind = kind
    }
}

nonisolated enum ActionRef: Codable, Hashable, Sendable {
    case builtIn(BuiltInAction)
    case custom(UUID)
}

/// Per-application layout for the contextual state.
nonisolated struct AppProfile: Codable, Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var isEnabled: Bool
    var actions: [ActionRef]

    var id: String { bundleID }

    static let defaults: [AppProfile] = [
        AppProfile(bundleID: "com.apple.dt.Xcode", name: "Xcode", isEnabled: true,
                   actions: [.builtIn(.xcodeBuild), .builtIn(.xcodeRun), .builtIn(.xcodeTest), .builtIn(.xcodeStop), .builtIn(.xcodeClean)]),
        AppProfile(bundleID: "com.apple.Safari", name: "Safari", isEnabled: true,
                   actions: [.builtIn(.safariNewTab), .builtIn(.safariReload), .builtIn(.safariCopyURL), .builtIn(.finderDownloads)]),
        AppProfile(bundleID: "com.apple.finder", name: "Finder", isEnabled: true,
                   actions: [.builtIn(.finderNewWindow), .builtIn(.finderHome), .builtIn(.finderDownloads), .builtIn(.finderDesktop), .builtIn(.finderCopyPath)]),
    ]
}
