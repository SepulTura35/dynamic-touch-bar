import Foundation
import Testing
@testable import DynamicTouchBar

@MainActor
@Suite("Island state machine")
struct IslandCoordinatorTests {
    let scheduler = ManualScheduler()

    private func make(_ configure: (inout IslandBehavior) -> Void = { _ in }) -> IslandCoordinator {
        var behavior = IslandBehavior()
        behavior.expandOnSummon = false
        behavior.autoCollapseDelay = 4
        behavior.transientDuration = 2
        behavior.notificationDuration = 3
        configure(&behavior)
        let coordinator = IslandCoordinator(behavior: behavior, scheduler: scheduler)
        coordinator.setVisible(true)
        return coordinator
    }

    @Test func restsInMinimal() {
        let coordinator = make()
        #expect(coordinator.state == IslandLayoutState(primary: .minimal, secondary: nil))
    }

    @Test func tapExpandsToDashboardThenAutoCollapses() {
        let coordinator = make()
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .dashboard)
        scheduler.advance(by: 3.9)
        #expect(coordinator.state.primary == .dashboard)
        scheduler.advance(by: 0.2)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func interactionPostponesCollapse() {
        let coordinator = make()
        coordinator.tapCapsule()
        scheduler.advance(by: 3)
        coordinator.noteInteraction()
        scheduler.advance(by: 3)
        #expect(coordinator.state.primary == .dashboard)
        scheduler.advance(by: 1.1)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func autoCollapseCanBeDisabled() {
        let coordinator = make { $0.autoCollapse = false }
        coordinator.tapCapsule()
        scheduler.advance(by: 60)
        #expect(coordinator.state.primary == .dashboard)
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func musicIsCompactLiveActivityAndExpandsOnTap() {
        let coordinator = make()
        coordinator.setLiveActivity(.music, active: true)
        #expect(coordinator.state.primary == .music(expanded: false))
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .music(expanded: true))
        scheduler.advance(by: 5)
        #expect(coordinator.state.primary == .music(expanded: false))
        coordinator.setLiveActivity(.music, active: false)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func transientOverridesAndReturnsToResting() {
        let coordinator = make()
        coordinator.setLiveActivity(.music, active: true)
        coordinator.present(.volume)
        #expect(coordinator.state == IslandLayoutState(primary: .volume, secondary: nil))
        scheduler.advance(by: 2.1)
        #expect(coordinator.state.primary == .music(expanded: false))
    }

    @Test func repeatedTransientExtendsInsteadOfRestarting() {
        let coordinator = make()
        coordinator.present(.volume)
        scheduler.advance(by: 1.5)
        coordinator.present(.volume)
        scheduler.advance(by: 1.5)
        #expect(coordinator.state.primary == .volume)
        scheduler.advance(by: 0.6)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func notificationsQueueInOrder() {
        let coordinator = make()
        let first = UUID(), second = UUID()
        coordinator.present(.notification(first))
        coordinator.present(.notification(second))
        #expect(coordinator.state.primary == .notification(first))
        scheduler.advance(by: 3.1)
        #expect(coordinator.state.primary == .notification(second))
        scheduler.advance(by: 3.1)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func volumePreemptsNotificationWhichResumesAfterwards() {
        let coordinator = make()
        let id = UUID()
        coordinator.present(.notification(id))
        coordinator.present(.volume)
        #expect(coordinator.state.primary == .volume)
        scheduler.advance(by: 2.1)
        #expect(coordinator.state.primary == .notification(id))
    }

    @Test func notificationWaitsForInteractiveTransient() {
        let coordinator = make()
        let id = UUID()
        coordinator.present(.brightness)
        coordinator.present(.notification(id))
        #expect(coordinator.state.primary == .brightness)
        scheduler.advance(by: 2.1)
        #expect(coordinator.state.primary == .notification(id))
    }

    @Test func tapDismissesTransient() {
        let coordinator = make()
        coordinator.present(.battery)
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func hiddenIslandHoldsNotificationsOnly() {
        let coordinator = make()
        coordinator.setVisible(false)
        let id = UUID()
        coordinator.present(.volume)
        coordinator.present(.notification(id), holdWhenHidden: true)
        coordinator.present(.notification(UUID()), holdWhenHidden: false)
        #expect(coordinator.pendingTransientCount == 1)
        coordinator.setVisible(true)
        #expect(coordinator.state.primary == .notification(id))
    }

    @Test func staleHeldNotificationsAreDropped() {
        let coordinator = make()
        coordinator.setVisible(false)
        coordinator.present(.notification(UUID()), holdWhenHidden: true)
        scheduler.advance(by: 301)
        coordinator.setVisible(true)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func heldNotificationsAreCapped() {
        let coordinator = make()
        coordinator.setVisible(false)
        for _ in 0..<10 { coordinator.present(.notification(UUID()), holdWhenHidden: true) }
        #expect(coordinator.pendingTransientCount == 3)
    }

    @Test func secondLiveActivityBecomesBubbleAndCanBePromoted() {
        let coordinator = make()
        coordinator.setLiveActivity(.timer, active: true)
        coordinator.setLiveActivity(.music, active: true)
        #expect(coordinator.state == IslandLayoutState(primary: .music(expanded: false), secondary: .timer))
        coordinator.tapBubble()
        #expect(coordinator.state == IslandLayoutState(primary: .timer(expanded: false), secondary: .music))
        coordinator.setLiveActivity(.timer, active: false)
        #expect(coordinator.state == IslandLayoutState(primary: .music(expanded: false), secondary: nil))
    }

    @Test func priorityOrderIsConfigurable() {
        let coordinator = make { $0.livePriority = [.timer, .music, .progress] }
        coordinator.setLiveActivity(.music, active: true)
        coordinator.setLiveActivity(.timer, active: true)
        #expect(coordinator.state.primary == .timer(expanded: false))
        #expect(coordinator.state.secondary == .music)
    }

    @Test func bubbleHiddenDuringTransient() {
        let coordinator = make()
        coordinator.setLiveActivity(.music, active: true)
        coordinator.setLiveActivity(.timer, active: true)
        coordinator.present(.volume)
        #expect(coordinator.state.secondary == nil)
    }

    @Test func disabledModulesAreIgnored() {
        let coordinator = make { $0.enabledModules = Set(IslandModule.allCases).subtracting([.music, .volume]) }
        coordinator.setLiveActivity(.music, active: true)
        coordinator.present(.volume)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func disablingModuleWhileShowingEndsIt() {
        let coordinator = make()
        coordinator.present(.volume)
        var behavior = coordinator.behavior
        behavior.enabledModules.remove(.volume)
        coordinator.update(behavior: behavior)
        #expect(coordinator.state.primary == .minimal)
    }

    @Test func contextualDefaultShowsAppActionsWithMusicAsBubble() {
        let coordinator = make { $0.defaultState = .contextual }
        coordinator.setContextAvailable(true)
        coordinator.setLiveActivity(.music, active: true)
        #expect(coordinator.state == IslandLayoutState(primary: .contextual, secondary: .music))
        coordinator.tapBubble()
        #expect(coordinator.state.primary == .music(expanded: false))
    }

    @Test func contextualFallsBackWhenNoProfile() {
        let coordinator = make { $0.defaultState = .contextual }
        #expect(coordinator.state.primary == .minimal)
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .dashboard)
    }

    @Test func dashboardDefaultCollapsesOnTap() {
        let coordinator = make { $0.defaultState = .dashboard }
        #expect(coordinator.state.primary == .dashboard)
        coordinator.tapCapsule()
        #expect(coordinator.state.primary == .minimal)
        scheduler.advance(by: 4.1)
        #expect(coordinator.state.primary == .dashboard)
    }

    @Test func summonExpandsWhenConfigured() {
        var behavior = IslandBehavior()
        behavior.expandOnSummon = true
        let coordinator = IslandCoordinator(behavior: behavior, scheduler: scheduler)
        coordinator.setLiveActivity(.music, active: true)
        coordinator.setVisible(true)
        #expect(coordinator.state.primary == .music(expanded: true))
        scheduler.advance(by: behavior.autoCollapseDelay + 0.1)
        #expect(coordinator.state.primary == .music(expanded: false))
        coordinator.setVisible(false)
        #expect(coordinator.state.primary == .music(expanded: false))
    }

    @Test func hidingResetsTransientsAndExpansion() {
        let coordinator = make()
        coordinator.tapCapsule()
        coordinator.present(.volume)
        coordinator.setVisible(false)
        #expect(coordinator.state.primary == .minimal)
        #expect(scheduler.pendingCount == 0)
    }
}
