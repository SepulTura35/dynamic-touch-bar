import Combine
import Foundation

nonisolated enum PomodoroPhase: String, Equatable, Sendable {
    case work, shortBreak, longBreak

    var title: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }
}

nonisolated enum TimerKind: Equatable, Sendable {
    case countdown
    case focus
    case stopwatch
    case pomodoro(PomodoroPhase, round: Int)

    var symbol: String {
        switch self {
        case .countdown: "timer"
        case .focus: "moon.fill"
        case .stopwatch: "stopwatch.fill"
        case .pomodoro(let phase, _): phase == .work ? "leaf.fill" : "cup.and.saucer.fill"
        }
    }
}

nonisolated struct PomodoroConfig: Equatable, Sendable {
    var work: TimeInterval = 25 * 60
    var shortBreak: TimeInterval = 5 * 60
    var longBreak: TimeInterval = 15 * 60
    var rounds = 4
}

/// A running or paused timer. Times are wall-clock based: elapsed time is
/// `accumulated + (now - runningSince)`, so it is exact regardless of how often the UI
/// refreshes, whether the capsule is collapsed, or whether the Mac slept.
nonisolated struct TimerSession: Equatable, Sendable {
    var kind: TimerKind
    var label: String
    var duration: TimeInterval?
    var accumulated: TimeInterval = 0
    var runningSince: Date?

    var isRunning: Bool { runningSince != nil }
    var isStopwatch: Bool { duration == nil }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func remaining(at date: Date) -> TimeInterval? {
        duration.map { max(0, $0 - elapsed(at: date)) }
    }

    /// 0…1 progress for the ring (stopwatch: the current minute).
    func fraction(at date: Date) -> Double {
        if let duration, duration > 0 { return min(max(elapsed(at: date) / duration, 0), 1) }
        return elapsed(at: date).truncatingRemainder(dividingBy: 60) / 60
    }

    func displayTime(at date: Date) -> String {
        if let remaining = remaining(at: date) { return TimeFormat.countdown(remaining) }
        return TimeFormat.clock(elapsed(at: date))
    }
}

final class TimerEngine: ObservableObject {
    @Published private(set) var session: TimerSession?

    var pomodoro = PomodoroConfig()
    /// (finished session, automatically started follow-up session — pomodoro only)
    var onComplete: ((TimerSession, TimerSession?) -> Void)?

    private let scheduler: IslandScheduler
    private var completionToken: ScheduledToken?

    init(scheduler: IslandScheduler = MainScheduler.shared) {
        self.scheduler = scheduler
    }

    var isActive: Bool { session != nil }

    /// The engine's clock. Views read this instead of `Date()` so display and logic agree.
    var now: Date { scheduler.now }

    // MARK: Start

    func startCountdown(minutes: Double, label: String = "Timer") {
        begin(TimerSession(kind: .countdown, label: label, duration: max(1, minutes * 60)))
    }

    func startFocus(minutes: Double) {
        begin(TimerSession(kind: .focus, label: "Focus", duration: max(1, minutes * 60)))
    }

    func startStopwatch() {
        begin(TimerSession(kind: .stopwatch, label: "Stopwatch", duration: nil))
    }

    func startPomodoro() {
        begin(Self.pomodoroSession(.work, round: 1, config: pomodoro))
    }

    private func begin(_ newSession: TimerSession) {
        var running = newSession
        running.runningSince = scheduler.now
        session = running
        scheduleCompletion()
    }

    // MARK: Control

    func pause() {
        guard var current = session, current.isRunning else { return }
        current.accumulated = current.elapsed(at: scheduler.now)
        current.runningSince = nil
        session = current
        completionToken?.cancel()
    }

    func resume() {
        guard var current = session, !current.isRunning else { return }
        current.runningSince = scheduler.now
        session = current
        scheduleCompletion()
    }

    func togglePause() {
        guard let current = session else { return }
        current.isRunning ? pause() : resume()
    }

    func stop() {
        completionToken?.cancel()
        completionToken = nil
        session = nil
    }

    func addMinute() {
        guard var current = session, let duration = current.duration else { return }
        current.duration = duration + 60
        session = current
        scheduleCompletion()
    }

    /// Re-evaluates after sleep/wake (timers may have expired while asleep).
    func refresh() {
        guard let current = session, current.isRunning else { return }
        if let remaining = current.remaining(at: scheduler.now), remaining <= 0 {
            complete()
        } else {
            scheduleCompletion()
        }
    }

    // MARK: Completion

    private func scheduleCompletion() {
        completionToken?.cancel()
        completionToken = nil
        guard let current = session, current.isRunning, let remaining = current.remaining(at: scheduler.now) else { return }
        completionToken = scheduler.schedule(after: remaining) { [weak self] in self?.complete() }
    }

    private func complete() {
        guard var finished = session else { return }
        completionToken?.cancel()
        completionToken = nil
        finished.accumulated = finished.duration ?? finished.elapsed(at: scheduler.now)
        finished.runningSince = nil

        var next: TimerSession?
        if case .pomodoro(let phase, let round) = finished.kind {
            switch phase {
            case .work:
                let isLong = round % max(1, pomodoro.rounds) == 0
                next = Self.pomodoroSession(isLong ? .longBreak : .shortBreak, round: round, config: pomodoro)
            case .shortBreak:
                next = Self.pomodoroSession(.work, round: round + 1, config: pomodoro)
            case .longBreak:
                next = nil
            }
        }

        if let next {
            begin(next)
        } else {
            session = nil
        }
        onComplete?(finished, session)
    }

    static func pomodoroSession(_ phase: PomodoroPhase, round: Int, config: PomodoroConfig) -> TimerSession {
        let duration: TimeInterval = switch phase {
        case .work: config.work
        case .shortBreak: config.shortBreak
        case .longBreak: config.longBreak
        }
        let label = phase == .work ? "Focus \(round)/\(config.rounds)" : phase.title
        return TimerSession(kind: .pomodoro(phase, round: round), label: label, duration: duration)
    }
}
