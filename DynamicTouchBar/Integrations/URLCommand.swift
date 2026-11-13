import Foundation

/// `dynamictouchbar://` commands — the public integration surface for scripts, Xcode
/// Behaviors, Shortcuts and other apps. Parsing is pure and unit-tested; every string is
/// length-limited and every number clamped, since any app or web page can open a URL.
///
///     dynamictouchbar://show | hide | toggle | settings
///     dynamictouchbar://notify?title=Deploy%20done&body=All%20green&symbol=checkmark.seal.fill&duration=4
///     dynamictouchbar://progress?id=build&title=Building&value=0.42
///     dynamictouchbar://progress?id=build&state=done        (done | failed | cancel)
///     dynamictouchbar://timer?minutes=25&label=Tea
///     dynamictouchbar://timer/stop | stopwatch | pomodoro
nonisolated enum URLCommand: Equatable, Sendable {
    enum ProgressState: String, Equatable, Sendable { case running, done, failed, cancel }

    case show, hide, toggle, settings
    case notify(title: String, body: String?, symbol: String?, duration: TimeInterval?)
    case progress(id: String, title: String?, value: Double?, state: ProgressState)
    case timer(minutes: Double, label: String?)
    case stopTimer
    case stopwatch
    case pomodoro

    static let scheme = "dynamictouchbar"
    static let maxTextLength = 120

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme, let host = url.host?.lowercased() else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if let value = item.value { query[item.name.lowercased()] = value }
        }
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }

        func text(_ key: String) -> String? {
            guard let raw = query[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            return String(cleaned.prefix(maxTextLength))
        }
        func number(_ key: String) -> Double? {
            guard let raw = query[key], let value = Double(raw), value.isFinite else { return nil }
            return value
        }

        switch host {
        case "show": return .show
        case "hide": return .hide
        case "toggle": return .toggle
        case "settings": return .settings
        case "notify":
            guard let title = text("title") else { return nil }
            let symbol = text("symbol").flatMap { $0.range(of: "^[a-z0-9.]+$", options: .regularExpression) != nil ? $0 : nil }
            return .notify(title: title, body: text("body"), symbol: symbol, duration: number("duration").map { min(max($0, 1), 30) })
        case "progress":
            guard let rawID = text("id") else { return nil }
            let id = String(rawID.prefix(64))
            let state = text("state").flatMap { ProgressState(rawValue: $0.lowercased()) } ?? .running
            var value = number("value")
            if let v = value, v > 1, v <= 100 { value = v / 100 } // accept percentages
            return .progress(id: id, title: text("title"), value: value.map { min(max($0, 0), 1) }, state: state)
        case "timer":
            if path.first == "stop" { return .stopTimer }
            guard let minutes = number("minutes"), minutes > 0 else { return nil }
            return .timer(minutes: min(minutes, 24 * 60), label: text("label"))
        case "stopwatch": return .stopwatch
        case "pomodoro": return .pomodoro
        default: return nil
        }
    }
}
