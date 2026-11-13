import Foundation

nonisolated enum TimeFormat {
    /// 0:42, 3:21, 1:02:03. Negative and non-finite values clamp to 0.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Countdowns round *up* so "0:00" only appears at completion.
    static func countdown(_ seconds: TimeInterval) -> String {
        clock(seconds.isFinite ? max(0, seconds.rounded(.up)) : 0)
    }

    /// Stopwatch with tenths: 1:02.3
    static func stopwatch(_ seconds: TimeInterval) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        let tenths = Int((value * 10).rounded(.down)) % 10
        return clock(value) + ".\(tenths)"
    }

    /// "1 h 20 min", "45 min", "under 1 min"
    static func duration(minutes: Int) -> String {
        if minutes <= 0 { return "under 1 min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }
}

nonisolated enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated extension String {
    /// Truncates to `limit` characters with an ellipsis, collapsing whitespace runs.
    func truncatedForPreview(_ limit: Int) -> String {
        let collapsed = split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard collapsed.count > limit, limit > 1 else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}
