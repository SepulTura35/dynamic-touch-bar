import Foundation
import Testing
@testable import DynamicTouchBar

@MainActor
@Suite("Spring physics")
struct SpringTests {
    private func run(_ spring: inout SpringValue, seconds: Double, dt: Double = 1.0 / 60.0) -> [Double] {
        var values: [Double] = []
        var t = 0.0
        while t < seconds {
            spring.step(dt)
            values.append(spring.value)
            t += dt
        }
        return values
    }

    @Test func convergesAndSettlesExactlyOnTarget() {
        var spring = SpringValue(0, parameters: .smooth)
        spring.retarget(100)
        _ = run(&spring, seconds: 3)
        #expect(spring.isSettled)
        #expect(spring.value == 100)
        #expect(spring.velocity == 0)
    }

    @Test func criticallyDampedNeverOvershoots() {
        var spring = SpringValue(0, parameters: SpringParameters(response: 0.4, dampingFraction: 1))
        spring.retarget(1)
        let values = run(&spring, seconds: 2)
        #expect(values.allSatisfy { $0 <= 1.0000001 })
    }

    @Test func overdampedNeverOvershoots() {
        var spring = SpringValue(0, parameters: SpringParameters(response: 0.4, dampingFraction: 1.6))
        spring.retarget(1)
        let values = run(&spring, seconds: 4)
        #expect(values.allSatisfy { $0 <= 1.0000001 })
        #expect(abs(spring.value - 1) < 0.01)
    }

    @Test func underdampedOvershootsThenSettles() {
        var spring = SpringValue(0, parameters: .bouncy)
        spring.retarget(1)
        let values = run(&spring, seconds: 3)
        #expect(values.max()! > 1.01)
        #expect(spring.isSettled)
    }

    @Test func frameRateIndependent() {
        var at60 = SpringValue(0, parameters: .bouncy, restThreshold: 0)
        var at120 = SpringValue(0, parameters: .bouncy, restThreshold: 0)
        at60.retarget(1)
        at120.retarget(1)
        for _ in 0..<30 { at60.step(1.0 / 60.0) }
        for _ in 0..<60 { at120.step(1.0 / 120.0) }
        #expect(abs(at60.value - at120.value) < 1e-9)
        #expect(abs(at60.velocity - at120.velocity) < 1e-9)
    }

    @Test func largeFrameHitchStaysStable() {
        var spring = SpringValue(0, parameters: .bouncy)
        spring.retarget(500)
        spring.step(5)
        #expect(spring.value.isFinite)
        #expect(abs(spring.value - 500) < 1)
    }

    @Test func retargetPreservesValueAndVelocity() {
        var spring = SpringValue(0, parameters: .smooth)
        spring.retarget(100)
        for _ in 0..<10 { spring.step(1.0 / 60.0) }
        let value = spring.value
        let velocity = spring.velocity
        spring.retarget(-50)
        #expect(spring.value == value)
        #expect(spring.velocity == velocity)
        #expect(!spring.isSettled)
    }

    @Test func fasterSpeedSettlesSooner() {
        let normal = SpringSolver.settlingDuration(.smooth)
        let fast = SpringSolver.settlingDuration(.smooth.scaled(speed: 2))
        #expect(fast < normal * 0.6)
    }

    @Test func snapSettlesImmediately() {
        var spring = SpringValue(0)
        spring.retarget(10)
        spring.step(0.016)
        spring.snap(to: 3)
        #expect(spring.isSettled && spring.value == 3 && spring.target == 3)
    }
}

@MainActor
@Suite("Capsule animator")
struct CapsuleAnimatorTests {
    private func target(_ id: String, width: Double = 200, bubble: BubbleTarget? = nil) -> CapsuleTarget {
        CapsuleTarget(width: width, height: 30, centerX: 342, cornerRadius: 15, contentID: id, glow: 0, bubble: bubble)
    }

    private func settle(_ animator: inout CapsuleAnimator, seconds: Double = 3) -> [String] {
        var removed: [String] = []
        var t = 0.0
        while t < seconds {
            removed += animator.step(1.0 / 60.0).removedContent
            t += 1.0 / 60.0
        }
        return removed
    }

    @Test func firstApplySnapsWithoutAnimation() {
        var animator = CapsuleAnimator()
        animator.apply(target("minimal", width: 128), animated: true)
        #expect(animator.width.value == 128)
        #expect(animator.slots.count == 1)
        #expect(animator.slots[0].presence.value == 1)
        #expect(!animator.isAnimating)
    }

    @Test func transitionCrossFadesAndRemovesOldContent() {
        var animator = CapsuleAnimator()
        animator.apply(target("minimal", width: 128), animated: false)
        animator.apply(target("volume", width: 330), animated: true)
        #expect(animator.currentContentID == "volume")
        #expect(animator.slots.count == 2)
        #expect(animator.isAnimating)
        let removed = settle(&animator)
        #expect(removed == ["minimal"])
        #expect(animator.slots.map(\.id) == ["volume"])
        #expect(animator.width.value == 330)
        #expect(!animator.isAnimating)
    }

    @Test func interruptedTransitionRevivesDepartingContent() {
        var animator = CapsuleAnimator()
        animator.apply(target("minimal", width: 128), animated: false)
        animator.apply(target("volume", width: 330), animated: true)
        for _ in 0..<6 { animator.step(1.0 / 60.0) }
        let minimalPresence = animator.slots.first { $0.id == "minimal" }!.presence.value
        let widthBefore = animator.width.value
        let velocityBefore = animator.width.velocity

        // Back to minimal mid-flight: no new slot, continue from current opacity and momentum.
        animator.apply(target("minimal", width: 128), animated: true)
        #expect(animator.slots.count == 2)
        #expect(animator.currentContentID == "minimal")
        #expect(animator.slots.first { $0.id == "minimal" }!.presence.value == minimalPresence)
        #expect(animator.width.value == widthBefore)
        #expect(animator.width.velocity == velocityBefore)

        let removed = settle(&animator)
        #expect(removed == ["volume"])
        #expect(animator.width.value == 128)
    }

    @Test func sameContentOnlyRetargetsGeometry() {
        var animator = CapsuleAnimator()
        animator.apply(target("notification", width: 260), animated: false)
        animator.apply(target("notification", width: 300), animated: true)
        #expect(animator.slots.count == 1)
        #expect(animator.slots[0].presence.isSettled)
        _ = settle(&animator)
        #expect(animator.width.value == 300)
    }

    @Test func bubbleAppearsAndRetracts() {
        var animator = CapsuleAnimator()
        animator.apply(target("music.compact", width: 168), animated: false)
        let bubble = BubbleTarget(contentID: "bubble.timer", diameter: 24, centerX: 450)
        animator.apply(target("music.compact", width: 168, bubble: bubble), animated: true)
        _ = settle(&animator)
        #expect(animator.bubblePresence.value == 1)
        #expect(animator.bubbleCenterX.value == 450)
        #expect(animator.currentBubbleContentID == "bubble.timer")

        animator.apply(target("music.compact", width: 168), animated: true)
        var removedBubble: [String] = []
        for _ in 0..<180 { removedBubble += animator.step(1.0 / 60.0).removedBubbleContent }
        #expect(animator.bubblePresence.value == 0)
        #expect(removedBubble == ["bubble.timer"])
        #expect(animator.bubbleSlots.isEmpty)
    }

    @Test func rapidChangesNeverAccumulateSlots() {
        var animator = CapsuleAnimator()
        animator.apply(target("a"), animated: false)
        for index in 0..<50 {
            animator.apply(target(["a", "b", "c"][index % 3], width: Double(100 + index * 7)), animated: true)
            animator.step(1.0 / 120.0)
        }
        #expect(animator.slots.count <= 3)
        _ = settle(&animator)
        #expect(animator.slots.count == 1)
    }
}
