import AppKit

/// Executes parsed URL commands with simple flood protection for notifications.
final class URLSchemeHandler {
    private unowned let env: AppEnvironment
    private let summon: SummonController
    private var recentNotifications: [Date] = []

    init(env: AppEnvironment, summon: SummonController) {
        self.env = env
        self.summon = summon
    }

    func handle(_ url: URL) {
        guard let command = URLCommand.parse(url) else {
            Log.app.error("Ignored unrecognised URL command")
            return
        }
        switch command {
        case .show: summon.summon()
        case .hide: if summon.isSummoned { summon.dismiss() }
        case .toggle: summon.toggle()
        case .settings: env.openSettings?()
        case .notify(let title, let body, let symbol, let duration):
            guard allowNotification() else { return }
            let resolvedSymbol = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil } ?? "app.badge.fill"
            env.notifications.post(IslandNotification(source: .custom, title: title, subtitle: body, symbol: resolvedSymbol,
                                                      tint: .controlAccentColor, duration: duration))
        case .progress(let id, let title, let value, let state):
            switch state {
            case .running: env.progress.upsert(id: id, title: title, fraction: value)
            case .done: env.progress.finish(id: id, success: true)
            case .failed: env.progress.finish(id: id, success: false)
            case .cancel: env.progress.cancel(id: id)
            }
        case .timer(let minutes, let label): env.timer.startCountdown(minutes: minutes, label: label ?? "Timer")
        case .stopTimer: env.timer.stop()
        case .stopwatch: env.timer.startStopwatch()
        case .pomodoro: env.timer.startPomodoro()
        }
    }

    /// At most 6 custom notifications per 10 seconds.
    private func allowNotification() -> Bool {
        let now = Date()
        recentNotifications.removeAll { now.timeIntervalSince($0) > 10 }
        guard recentNotifications.count < 6 else { return false }
        recentNotifications.append(now)
        return true
    }
}
