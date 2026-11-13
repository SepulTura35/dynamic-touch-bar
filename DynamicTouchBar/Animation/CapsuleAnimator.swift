import Foundation

/// Where the capsule should end up. Produced by the island view from the current
/// presentation and consumed by `CapsuleAnimator`.
nonisolated struct CapsuleTarget: Equatable, Sendable {
    var width: Double
    var height: Double
    var centerX: Double
    var cornerRadius: Double
    var contentID: String
    var glow: Double
    var bubble: BubbleTarget?
}

/// The detached secondary bubble (Dynamic Island "split" for a second live activity).
nonisolated struct BubbleTarget: Equatable, Sendable {
    var contentID: String
    var diameter: Double
    var centerX: Double
}

/// One piece of content inside the capsule. `presence` runs 0 (gone) → 1 (fully shown).
nonisolated struct ContentSlot: Equatable, Sendable {
    let id: String
    var presence: SpringValue
    var isCurrent: Bool
}

/// Pure, deterministic animation model for the island. No AppKit — fully unit-testable.
///
/// Rules that give the island its continuity:
/// * Geometry (width/height/center/corner) is one set of springs that is *retargeted*, never
///   restarted, so an interruption mid-flight keeps its momentum.
/// * Content that is replaced becomes a departing slot and fades out with a critically damped
///   spring; the new content fades in on the main spring.
/// * If content that is still departing becomes current again (A → B → A quickly), the
///   departing slot is revived from its present opacity instead of creating a new one — no flicker.
nonisolated struct CapsuleAnimator: Sendable {
    private(set) var width = SpringValue(0, restThreshold: 0.05)
    private(set) var height = SpringValue(0, restThreshold: 0.02)
    private(set) var centerX = SpringValue(0, restThreshold: 0.05)
    private(set) var cornerRadius = SpringValue(0, restThreshold: 0.02)
    private(set) var glow = SpringValue(0)
    private(set) var bubblePresence = SpringValue(0)
    private(set) var bubbleCenterX = SpringValue(0, restThreshold: 0.05)
    private(set) var bubbleDiameter = SpringValue(0, restThreshold: 0.02)

    private(set) var slots: [ContentSlot] = []
    private(set) var bubbleSlots: [ContentSlot] = []
    private(set) var hasAppliedTarget = false

    var parameters: SpringParameters = .smooth

    init(parameters: SpringParameters = .smooth) {
        self.parameters = parameters
    }

    var currentContentID: String? { slots.first(where: \.isCurrent)?.id }
    var currentBubbleContentID: String? { bubbleSlots.first(where: \.isCurrent)?.id }

    var isAnimating: Bool {
        !width.isSettled || !height.isSettled || !centerX.isSettled || !cornerRadius.isSettled
            || !glow.isSettled || !bubblePresence.isSettled || !bubbleCenterX.isSettled
            || !bubbleDiameter.isSettled
            || slots.contains { !$0.presence.isSettled || !$0.isCurrent }
            || bubbleSlots.contains { !$0.presence.isSettled || !$0.isCurrent }
    }

    private var exitParameters: SpringParameters {
        SpringParameters(response: parameters.response * 0.55, dampingFraction: 1)
    }

    private var contentParameters: SpringParameters {
        // Content settles a touch faster than geometry and never bounces in opacity.
        SpringParameters(response: parameters.response * 0.8, dampingFraction: max(parameters.dampingFraction, 0.95))
    }

    /// Moves everything toward `target`. With `animated == false` it snaps.
    mutating func apply(_ target: CapsuleTarget, animated: Bool) {
        let animate = animated && hasAppliedTarget
        hasAppliedTarget = true

        func drive(_ spring: inout SpringValue, _ value: Double, _ params: SpringParameters) {
            if animate { spring.retarget(value, parameters: params) } else { spring.parameters = params; spring.snap(to: value) }
        }

        drive(&width, target.width, parameters)
        drive(&height, target.height, parameters)
        drive(&centerX, target.centerX, parameters)
        drive(&cornerRadius, target.cornerRadius, parameters)
        drive(&glow, target.glow, contentParameters)

        Self.transition(&slots, to: target.contentID, animate: animate, enter: contentParameters, exit: exitParameters)

        if let bubble = target.bubble {
            let wasHidden = bubblePresence.target == 0
            if wasHidden && animate {
                // Bubble emerges from the capsule's trailing edge.
                bubbleCenterX.snap(to: target.centerX + target.width / 2 - bubble.diameter / 2)
                bubbleDiameter.snap(to: bubble.diameter * 0.6)
            }
            drive(&bubblePresence, 1, parameters)
            drive(&bubbleCenterX, bubble.centerX, parameters)
            drive(&bubbleDiameter, bubble.diameter, parameters)
            Self.transition(&bubbleSlots, to: bubble.contentID, animate: animate, enter: contentParameters, exit: exitParameters)
        } else {
            // Retract into the capsule's trailing edge.
            drive(&bubblePresence, 0, exitParameters)
            drive(&bubbleCenterX, target.centerX + target.width / 2 - bubbleDiameter.target / 2, parameters)
            for index in bubbleSlots.indices {
                bubbleSlots[index].isCurrent = false
                if animate {
                    bubbleSlots[index].presence.retarget(0, parameters: exitParameters)
                } else {
                    bubbleSlots[index].presence.snap(to: 0)
                }
            }
            if !animate { bubbleSlots.removeAll() }
        }
    }

    private static func transition(
        _ slots: inout [ContentSlot],
        to id: String,
        animate: Bool,
        enter: SpringParameters,
        exit: SpringParameters
    ) {
        if slots.first(where: \.isCurrent)?.id == id { return }

        for index in slots.indices where slots[index].isCurrent {
            slots[index].isCurrent = false
            if animate {
                slots[index].presence.retarget(0, parameters: exit)
            } else {
                slots[index].presence.snap(to: 0)
            }
        }

        if let index = slots.firstIndex(where: { $0.id == id }) {
            // Revive a slot that was on its way out: continue from its present opacity.
            slots[index].isCurrent = true
            slots[index].presence.retarget(1, parameters: enter)
            let revived = slots.remove(at: index)
            slots.append(revived)
        } else {
            var presence = SpringValue(animate ? 0 : 1, parameters: enter)
            if animate { presence.retarget(1) }
            slots.append(ContentSlot(id: id, presence: presence, isCurrent: true))
        }

        if !animate { slots.removeAll { !$0.isCurrent } }
    }

    /// Advances all springs. Returns the ids of content slots that finished leaving
    /// (the view should remove those views).
    @discardableResult
    mutating func step(_ dt: Double) -> (removedContent: [String], removedBubbleContent: [String]) {
        width.step(dt)
        height.step(dt)
        centerX.step(dt)
        cornerRadius.step(dt)
        glow.step(dt)
        bubblePresence.step(dt)
        bubbleCenterX.step(dt)
        bubbleDiameter.step(dt)

        for index in slots.indices { slots[index].presence.step(dt) }
        for index in bubbleSlots.indices { bubbleSlots[index].presence.step(dt) }

        let removed = slots.filter { !$0.isCurrent && $0.presence.isSettled }.map(\.id)
        slots.removeAll { !$0.isCurrent && $0.presence.isSettled }

        let removedBubble = bubbleSlots.filter { !$0.isCurrent && $0.presence.isSettled }.map(\.id)
        bubbleSlots.removeAll { !$0.isCurrent && $0.presence.isSettled }

        return (removed, removedBubble)
    }

    /// Re-tunes all running springs (e.g. user changed animation style mid-animation).
    mutating func updateParameters(_ newParameters: SpringParameters) {
        parameters = newParameters
        width.parameters = newParameters
        height.parameters = newParameters
        centerX.parameters = newParameters
        cornerRadius.parameters = newParameters
        bubbleCenterX.parameters = newParameters
        bubbleDiameter.parameters = newParameters
    }
}
