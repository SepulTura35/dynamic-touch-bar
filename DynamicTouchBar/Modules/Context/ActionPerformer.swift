import AppKit

/// Resolved, displayable action (built-in or custom).
struct ResolvedAction: Identifiable {
    let ref: ActionRef
    let title: String
    let symbol: String

    var id: String {
        switch ref {
        case .builtIn(let action): "builtin.\(action.rawValue)"
        case .custom(let uuid): "custom.\(uuid.uuidString)"
        }
    }
}

/// Executes quick actions. Every mechanism is public and permission-respecting:
/// the target app's scripting dictionary (Automation permission), `NSWorkspace`, or URL schemes.
final class ActionPerformer {
    enum Outcome {
        /// The island keeps focus (e.g. a timer started).
        case stay
        /// Hand focus back to the app the user came from.
        case returnFocus
    }

    private let settings: SettingsStore
    private let music: MusicModel
    private let timer: TimerEngine
    private let volume: VolumeModel
    private let notifications: NotificationsModel

    init(settings: SettingsStore, music: MusicModel, timer: TimerEngine, volume: VolumeModel, notifications: NotificationsModel) {
        self.settings = settings
        self.music = music
        self.timer = timer
        self.volume = volume
        self.notifications = notifications
    }

    func resolve(_ refs: [ActionRef]) -> [ResolvedAction] {
        refs.compactMap { ref in
            switch ref {
            case .builtIn(let action):
                return ResolvedAction(ref: ref, title: action.title, symbol: action.symbol)
            case .custom(let id):
                guard let custom = settings.settings.customActions.first(where: { $0.id == id }) else { return nil }
                return ResolvedAction(ref: ref, title: custom.title, symbol: custom.symbol)
            }
        }
    }

    @discardableResult
    func perform(_ ref: ActionRef) -> Outcome {
        switch ref {
        case .builtIn(let action): return perform(action)
        case .custom(let id):
            guard let custom = settings.settings.customActions.first(where: { $0.id == id }) else { return .stay }
            return perform(custom)
        }
    }

    // MARK: - Built-in

    @discardableResult
    func perform(_ action: BuiltInAction) -> Outcome {
        switch action {
        case .mediaPlayPause: music.playPause(); return .stay
        case .mediaNext: music.nextTrack(); return .stay
        case .mediaPrevious: music.previousTrack(); return .stay
        case .toggleMute: volume.toggleMute(); return .stay
        case .startPomodoro: timer.startPomodoro(); return .stay
        case .startTimer5: timer.startCountdown(minutes: 5); return .stay
        case .startTimer15: timer.startCountdown(minutes: 15); return .stay
        case .startStopwatch: timer.startStopwatch(); return .stay

        case .xcodeBuild: xcode("build"); return .returnFocus
        case .xcodeRun: xcode("run"); return .returnFocus
        case .xcodeTest: xcode("test"); return .returnFocus
        case .xcodeStop: xcode("stop"); return .returnFocus
        case .xcodeClean: xcode("clean"); return .returnFocus

        case .safariNewTab:
            script(action, """
            tell application "Safari"
                if (count of windows) is 0 then
                    make new document
                else
                    tell front window to set current tab to (make new tab)
                end if
                activate
            end tell
            """)
            return .stay
        case .safariReload:
            script(action, """
            tell application "Safari"
                if (count of documents) > 0 then
                    tell front document to set URL to (get URL)
                end if
            end tell
            """)
            return .returnFocus
        case .safariCopyURL:
            copyResult(of: """
            tell application "Safari"
                if (count of documents) is 0 then return ""
                return URL of front document
            end tell
            """, label: "Copied page link", action: action)
            return .stay

        case .finderNewWindow:
            script(action, """
            tell application "Finder"
                make new Finder window
                activate
            end tell
            """)
            return .stay
        case .finderHome: openFolder(.userDirectory); return .stay
        case .finderDownloads: openFolder(.downloadsDirectory); return .stay
        case .finderDesktop: openFolder(.desktopDirectory); return .stay
        case .finderApplications: openFolder(.applicationDirectory, domain: .localDomainMask); return .stay
        case .finderCopyPath:
            copyResult(of: """
            tell application "Finder"
                set sel to selection
                if (count of sel) is 0 then return ""
                return POSIX path of ((item 1 of sel) as alias)
            end tell
            """, label: "Copied file path", action: action)
            return .stay

        case .openScreenshot:
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .stay
        }
    }

    private func xcode(_ verb: String) {
        let source = """
        tell application "Xcode"
            set ws to active workspace document
            \(verb) ws
        end tell
        """
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty else {
            notifyFailure(title: "Xcode isn't running", symbol: "hammer")
            return
        }
        AppleScriptRunner.run(source) { [weak self] error in
            if let error { self?.handle(error, appName: "Xcode") }
        }
    }

    private func script(_ action: BuiltInAction, _ source: String) {
        AppleScriptRunner.run(source) { [weak self] error in
            if let error { self?.handle(error, appName: action.category.rawValue) }
        }
    }

    private func copyResult(of source: String, label: String, action: BuiltInAction) {
        AppleScriptRunner.run(source, parse: { $0.stringValue }) { [weak self] result in
            switch result {
            case .success(let value?) where !value.isEmpty:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                self?.notifications.post(IslandNotification(source: .system, title: label, subtitle: value.truncatedForPreview(48),
                                                            symbol: "checkmark.circle.fill", tint: .systemGreen, duration: 2),
                                         holdWhenHidden: false)
            case .success:
                self?.notifyFailure(title: "Nothing to copy", symbol: action.symbol)
            case .failure(let error):
                self?.handle(error, appName: action.category.rawValue)
            }
        }
    }

    private func openFolder(_ directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask = .userDomainMask) {
        let url: URL? = directory == .userDirectory
            ? FileManager.default.homeDirectoryForCurrentUser
            : FileManager.default.urls(for: directory, in: domain).first
        if let url { NSWorkspace.shared.open(url) }
    }

    private func handle(_ error: AppleScriptError, appName: String) {
        if error.isNotAuthorized {
            notifyFailure(title: "Allow \(appName) Automation", subtitle: "System Settings ▸ Privacy & Security ▸ Automation", symbol: "lock.shield.fill")
        } else if error.isAppNotRunning {
            notifyFailure(title: "\(appName) isn't running", symbol: "exclamationmark.circle")
        } else {
            notifyFailure(title: "\(appName) action failed", subtitle: error.message, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func notifyFailure(title: String, subtitle: String? = nil, symbol: String) {
        notifications.post(IslandNotification(source: .system, title: title, subtitle: subtitle, symbol: symbol,
                                              tint: .systemOrange, duration: 3), holdWhenHidden: false)
    }

    // MARK: - Custom

    @discardableResult
    func perform(_ custom: CustomAction) -> Outcome {
        switch custom.kind {
        case .openURL(let string):
            guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                notifyFailure(title: "Invalid link", subtitle: string, symbol: "link")
                return .stay
            }
            NSWorkspace.shared.open(url)
            return .stay
        case .openApp(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                notifyFailure(title: "App not found", subtitle: bundleID, symbol: "app.dashed")
                return .stay
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .stay
        case .runShortcut(let name):
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            if let url = components.url { NSWorkspace.shared.open(url) }
            return .returnFocus
        }
    }
}
