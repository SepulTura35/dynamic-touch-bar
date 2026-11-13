import Combine
import Foundation

nonisolated struct ProgressTask: Identifiable, Equatable, Sendable {
    enum State: String, Equatable, Sendable { case running, succeeded, failed }

    let id: String
    var title: String
    /// nil = indeterminate.
    var fraction: Double?
    var detail: String?
    var symbol: String
    var state: State
    var updatedAt: Date
}

/// Progress for integrations the app explicitly implements: the `dynamictouchbar://progress`
/// URL scheme (Xcode build scripts, shell scripts, Shortcuts) and the opt-in Downloads
/// folder watcher. It does not claim to see arbitrary system downloads.
final class ProgressCenter: ObservableObject {
    @Published private(set) var tasks: [ProgressTask] = []

    /// Called once when a task finishes.
    var onFinish: ((ProgressTask) -> Void)?

    private let scheduler: IslandScheduler
    private var staleTokens: [String: ScheduledToken] = [:]
    static let staleTimeout: TimeInterval = 15 * 60

    init(scheduler: IslandScheduler = MainScheduler.shared) {
        self.scheduler = scheduler
    }

    var running: [ProgressTask] { tasks.filter { $0.state == .running } }
    var primary: ProgressTask? { running.max { $0.updatedAt < $1.updatedAt } }
    var isActive: Bool { !running.isEmpty }

    func upsert(id: String, title: String?, fraction: Double?, detail: String? = nil, symbol: String? = nil) {
        let clampedFraction = fraction.map { min(max($0, 0), 1) }
        let now = scheduler.now
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            if let title, !title.isEmpty { tasks[index].title = title }
            tasks[index].fraction = clampedFraction
            if let detail { tasks[index].detail = detail }
            if let symbol { tasks[index].symbol = symbol }
            tasks[index].state = .running
            tasks[index].updatedAt = now
        } else {
            tasks.append(ProgressTask(id: id, title: (title?.isEmpty == false ? title : nil) ?? "Working…",
                                      fraction: clampedFraction, detail: detail, symbol: symbol ?? "arrow.triangle.2.circlepath",
                                      state: .running, updatedAt: now))
        }
        armStaleTimer(for: id)
    }

    func finish(id: String, success: Bool, detail: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = success ? .succeeded : .failed
        if success { tasks[index].fraction = 1 }
        if let detail { tasks[index].detail = detail }
        tasks[index].updatedAt = scheduler.now
        let finished = tasks[index]
        staleTokens[id]?.cancel()
        staleTokens[id] = nil
        tasks.remove(at: index)
        onFinish?(finished)
    }

    func cancel(id: String) {
        staleTokens[id]?.cancel()
        staleTokens[id] = nil
        tasks.removeAll { $0.id == id }
    }

    /// A task with no updates for 15 minutes is dropped so a crashed script can't leave a
    /// spinner on the island forever.
    private func armStaleTimer(for id: String) {
        staleTokens[id]?.cancel()
        staleTokens[id] = scheduler.schedule(after: Self.staleTimeout) { [weak self] in
            self?.staleTokens[id] = nil
            self?.tasks.removeAll { $0.id == id }
        }
    }
}
