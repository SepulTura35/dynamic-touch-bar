import Combine
import Foundation

/// Tunables for the state machine, derived from user settings.
nonisolated struct IslandBehavior: Equatable, Sendable {
    var defaultState: DefaultIslandState = .minimal
    var expandOnSummon = true
    var autoCollapse = true
    var autoCollapseDelay: TimeInterval = 4
    /// How long volume / brightness / battery / clipboard stay up.
    var transientDuration: TimeInterval = 2.4
    var notificationDuration: TimeInterval = 4
    var livePriority: [LiveActivityKind] = [.music, .timer, .progress]
    var enabledModules: Set<IslandModule> = Set(IslandModule.allCases)
    /// Notifications that arrive while the island isn't on the Touch Bar are kept
    /// (up to this many, for up to `heldNotificationMaxAge`) and shown on next summon.
    var heldNotificationLimit = 3
    var heldNotificationMaxAge: TimeInterval = 300
}

/// The island's brain: merges live activities, transient events, user taps, visibility and
/// app context into one `IslandLayoutState`. Pure logic — no views, no system APIs — and
/// driven by an injectable scheduler so every transition is unit-tested.
final class IslandCoordinator: ObservableObject {
    @Published private(set) var state = IslandLayoutState.initial

    private(set) var behavior: IslandBehavior
    private let scheduler: IslandScheduler

    private(set) var activeLiveActivities: Set<LiveActivityKind> = []
    private(set) var promoted: LiveActivityKind?
    /// `nil` = follow the resting state; `true/false` = user (or summon) override.
    private(set) var expansionOverride: Bool?
    private(set) var isVisible = false
    private(set) var isContextAvailable = false

    private struct TransientRequest: Equatable {
        let kind: TransientKind
        let duration: TimeInterval
        let createdAt: Date
    }

    private var currentTransient: TransientRequest?
    private var pendingTransients: [TransientRequest] = []
    private var transientToken: ScheduledToken?
    private var collapseToken: ScheduledToken?

    init(behavior: IslandBehavior = IslandBehavior(), scheduler: IslandScheduler = MainScheduler.shared) {
        self.behavior = behavior
        self.scheduler = scheduler
    }

    var currentTransientKind: TransientKind? { currentTransient?.kind }
    var pendingTransientCount: Int { pendingTransients.count }

    // MARK: - Inputs

    func update(behavior newBehavior: IslandBehavior) {
        guard newBehavior != behavior else { return }
        behavior = newBehavior
        if !behavior.autoCollapse {
            collapseToken?.cancel()
            collapseToken = nil
        }
        pendingTransients.removeAll { !behavior.enabledModules.contains($0.kind.module) }
        if let current = currentTransient, !behavior.enabledModules.contains(current.kind.module) {
            endCurrentTransient()
            return
        }
        recompute()
    }

    func setLiveActivity(_ kind: LiveActivityKind, active: Bool) {
        let changed = active ? activeLiveActivities.insert(kind).inserted : activeLiveActivities.remove(kind) != nil
        guard changed else { return }
        if !active && promoted == kind { promoted = nil }
        recompute()
    }

    func setContextAvailable(_ available: Bool) {
        guard available != isContextAvailable else { return }
        isContextAvailable = available
        recompute()
    }

    /// Called when the island appears on / leaves the physical Touch Bar (app activation).
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            promoted = nil
            if behavior.expandOnSummon {
                expansionOverride = true
                scheduleCollapse()
            }
            dropStaleHeldNotifications()
            if currentTransient == nil, !pendingTransients.isEmpty {
                showTransient(pendingTransients.removeFirst())
                return
            }
        } else {
            collapseToken?.cancel()
            collapseToken = nil
            expansionOverride = nil
            transientToken?.cancel()
            transientToken = nil
            // An unread notification goes back in line; everything else is momentary.
            if let current = currentTransient, current.kind.isNotification {
                pendingTransients.insert(current, at: 0)
            }
            currentTransient = nil
            pendingTransients.removeAll { !$0.kind.isNotification }
        }
        recompute()
    }

    /// Requests a transient presentation (volume change, notification, …).
    func present(_ kind: TransientKind, duration: TimeInterval? = nil, holdWhenHidden: Bool = false) {
        guard behavior.enabledModules.contains(kind.module) else { return }
        let resolvedDuration = duration ?? (kind.isNotification ? behavior.notificationDuration : behavior.transientDuration)
        let request = TransientRequest(kind: kind, duration: max(0.5, resolvedDuration), createdAt: scheduler.now)

        guard isVisible else {
            guard holdWhenHidden, kind.isNotification else { return }
            pendingTransients.append(request)
            if pendingTransients.count > behavior.heldNotificationLimit {
                pendingTransients.removeFirst(pendingTransients.count - behavior.heldNotificationLimit)
            }
            return
        }

        if let current = currentTransient {
            if current.kind == kind {
                // Same thing again (e.g. another volume step): keep it up, no re-animation.
                restartTransientTimer(duration: request.duration)
                return
            }
            if kind.isNotification {
                // Never yank an interactive control or another notification away: queue.
                pendingTransients.append(request)
                return
            }
            // Interactive transients (volume, brightness…) take over immediately; an
            // interrupted notification is put back at the front of the line.
            if current.kind.isNotification {
                pendingTransients.insert(current, at: 0)
            }
        }
        pendingTransients.removeAll { $0.kind == kind }
        showTransient(request)
    }

    func dismissTransient() {
        guard currentTransient != nil else { return }
        endCurrentTransient()
    }

    /// Removes a pending or visible notification (e.g. it became irrelevant).
    func withdraw(_ kind: TransientKind) {
        pendingTransients.removeAll { $0.kind == kind }
        if currentTransient?.kind == kind { endCurrentTransient() }
    }

    /// Any touch inside the island keeps it from collapsing under the user's finger.
    func noteInteraction() {
        if let current = currentTransient {
            restartTransientTimer(duration: current.duration)
        }
        if expansionOverride != nil { scheduleCollapse() }
    }

    /// Tap on the capsule background.
    func tapCapsule() {
        if currentTransient != nil {
            endCurrentTransient()
            return
        }
        expansionOverride = !resolvedExpanded()
        scheduleCollapse()
        recompute()
    }

    /// Tap on the secondary bubble: swap it into the main capsule.
    func tapBubble() {
        guard let secondary = state.secondary else { return }
        promoted = secondary
        expansionOverride = nil
        collapseToken?.cancel()
        recompute()
    }

    func expand() {
        expansionOverride = true
        scheduleCollapse()
        recompute()
    }

    func collapse() {
        if currentTransient != nil { endCurrentTransient() }
        expansionOverride = false
        scheduleCollapse()
        recompute()
    }

    // MARK: - Transient plumbing

    private func showTransient(_ request: TransientRequest) {
        currentTransient = request
        restartTransientTimer(duration: request.duration)
        recompute()
    }

    private func restartTransientTimer(duration: TimeInterval) {
        transientToken?.cancel()
        transientToken = scheduler.schedule(after: duration) { [weak self] in
            self?.endCurrentTransient()
        }
    }

    private func endCurrentTransient() {
        transientToken?.cancel()
        transientToken = nil
        currentTransient = nil
        dropStaleHeldNotifications()
        if isVisible, !pendingTransients.isEmpty {
            showTransient(pendingTransients.removeFirst())
        } else {
            recompute()
        }
    }

    private func dropStaleHeldNotifications() {
        let now = scheduler.now
        pendingTransients.removeAll { now.timeIntervalSince($0.createdAt) > behavior.heldNotificationMaxAge }
    }

    private func scheduleCollapse() {
        collapseToken?.cancel()
        collapseToken = nil
        guard behavior.autoCollapse, expansionOverride != nil else { return }
        collapseToken = scheduler.schedule(after: behavior.autoCollapseDelay) { [weak self] in
            guard let self else { return }
            self.expansionOverride = nil
            self.collapseToken = nil
            self.recompute()
        }
    }

    // MARK: - Resolution

    /// Live activities in user priority order (promoted one first), filtered by module.
    func orderedLiveActivities() -> [LiveActivityKind] {
        var order = behavior.livePriority
        for kind in LiveActivityKind.allCases where !order.contains(kind) { order.append(kind) }
        var result = order.filter { activeLiveActivities.contains($0) && behavior.enabledModules.contains($0.module) }
        if let promoted, let index = result.firstIndex(of: promoted) {
            result.remove(at: index)
            result.insert(promoted, at: 0)
        }
        return result
    }

    private var contextualAllowed: Bool {
        behavior.defaultState == .contextual && isContextAvailable && behavior.enabledModules.contains(.shortcuts)
    }

    private var contextTakesPrecedence: Bool { contextualAllowed && promoted == nil }

    private func restingExpanded(lives: [LiveActivityKind]) -> Bool {
        if !lives.isEmpty && !contextTakesPrecedence { return false }
        switch behavior.defaultState {
        case .minimal: return false
        case .dashboard: return true
        case .contextual: return contextualAllowed
        }
    }

    private func resolvedExpanded() -> Bool {
        expansionOverride ?? restingExpanded(lives: orderedLiveActivities())
    }

    private func content(for live: LiveActivityKind, expanded: Bool) -> PresentationContent {
        switch live {
        case .music: .music(expanded: expanded)
        case .timer: .timer(expanded: expanded)
        case .progress: .progress(expanded: expanded)
        }
    }

    private func content(for transient: TransientKind) -> PresentationContent {
        switch transient {
        case .volume: .volume
        case .brightness: .brightness
        case .battery: .battery
        case .clipboard: .clipboard
        case .notification(let id): .notification(id)
        }
    }

    func resolveState() -> IslandLayoutState {
        let lives = orderedLiveActivities()

        if let transient = currentTransient {
            return IslandLayoutState(primary: content(for: transient.kind), secondary: nil)
        }

        let expanded = expansionOverride ?? restingExpanded(lives: lives)

        if contextTakesPrecedence && expanded {
            return IslandLayoutState(primary: .contextual, secondary: lives.first)
        }
        if let top = lives.first {
            return IslandLayoutState(primary: content(for: top, expanded: expanded), secondary: lives.dropFirst().first)
        }
        if expanded {
            return IslandLayoutState(primary: contextualAllowed ? .contextual : .dashboard, secondary: nil)
        }
        return IslandLayoutState(primary: .minimal, secondary: nil)
    }

    private func recompute() {
        let next = resolveState()
        guard next != state else { return }
        Log.island.debug("State → \(next.primary.debugName, privacy: .public) bubble: \(next.secondary?.rawValue ?? "none", privacy: .public)")
        state = next
    }
}
