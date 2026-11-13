import Foundation

/// Handle for a scheduled action. Cancelling is idempotent.
final class ScheduledToken {
    private var cancelHandler: (() -> Void)?
    private(set) var isCancelled = false

    init(cancel: @escaping () -> Void) { cancelHandler = cancel }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancelHandler?()
        cancelHandler = nil
    }

    deinit { /* Tokens don't auto-cancel; owners cancel explicitly. */ }
}

/// Abstracts "run this later" and "what time is it" so state machines can be tested
/// deterministically without sleeping.
protocol IslandScheduler: AnyObject {
    var now: Date { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScheduledToken
}

/// Production scheduler on the main queue.
final class MainScheduler: IslandScheduler {
    static let shared = MainScheduler()

    var now: Date { Date() }

    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScheduledToken {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        // Wall-clock deadline: keeps firing at the right real-world time across sleep/wake
        // (a monotonic deadline would pause while the Mac sleeps).
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, delay), execute: item)
        return ScheduledToken { item.cancel() }
    }
}

/// Deterministic scheduler for tests: time only moves when `advance(by:)` is called.
final class ManualScheduler: IslandScheduler {
    private struct Entry {
        let id: Int
        let fireDate: Date
        let action: () -> Void
        let token: ScheduledToken
    }

    private(set) var now: Date
    private var entries: [Entry] = []
    private var nextID = 0

    init(now: Date = Date(timeIntervalSinceReferenceDate: 0)) { self.now = now }

    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScheduledToken {
        nextID += 1
        let id = nextID
        let token = ScheduledToken { [weak self] in self?.entries.removeAll { $0.id == id } }
        entries.append(Entry(id: id, fireDate: now.addingTimeInterval(max(0, delay)), action: action, token: token))
        return token
    }

    var pendingCount: Int { entries.count }

    func advance(by interval: TimeInterval) {
        let end = now.addingTimeInterval(interval)
        while let next = entries.filter({ $0.fireDate <= end }).min(by: { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }) {
            entries.removeAll { $0.id == next.id }
            now = max(now, next.fireDate)
            next.action()
        }
        now = end
    }
}
