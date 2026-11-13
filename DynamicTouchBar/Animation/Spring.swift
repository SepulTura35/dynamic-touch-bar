import Foundation

/// Spring tuning expressed the same way SwiftUI does: `response` is the period of the
/// undamped oscillation in seconds, `dampingFraction` is ζ (1 = critically damped).
nonisolated struct SpringParameters: Codable, Equatable, Hashable, Sendable {
    var response: Double
    var dampingFraction: Double

    init(response: Double, dampingFraction: Double) {
        self.response = max(0.02, response)
        self.dampingFraction = max(0.05, dampingFraction)
    }

    /// Calm, Apple-like default. Very slight overshoot.
    static let smooth = SpringParameters(response: 0.48, dampingFraction: 0.84)
    /// Playful, visible overshoot — closest to the iPhone island "pop".
    static let bouncy = SpringParameters(response: 0.52, dampingFraction: 0.68)
    /// Fast and tight. No visible overshoot.
    static let snappy = SpringParameters(response: 0.30, dampingFraction: 0.92)
    /// Slow and fully damped.
    static let gentle = SpringParameters(response: 0.70, dampingFraction: 1.0)

    /// Returns parameters for a different playback speed (2 = twice as fast).
    func scaled(speed: Double) -> SpringParameters {
        SpringParameters(response: response / min(max(speed, 0.25), 4), dampingFraction: dampingFraction)
    }

    /// Same spring with a different damping (used for exits, which should never bounce).
    func withDamping(_ damping: Double) -> SpringParameters {
        SpringParameters(response: response, dampingFraction: damping)
    }

    var angularFrequency: Double { 2 * .pi / response }
}

/// A single animated scalar driven by a damped harmonic oscillator.
///
/// The step function uses the closed-form solution of the spring ODE, so it is exact for
/// any time step: results do not depend on frame rate, and long frame hitches never make
/// the animation explode. Retargeting keeps the current value *and* velocity, which is what
/// makes interrupted animations continuous.
nonisolated struct SpringValue: Equatable, Sendable {
    private(set) var value: Double
    private(set) var velocity: Double
    private(set) var target: Double
    var parameters: SpringParameters
    /// Values closer than this to the target (with negligible velocity) snap and settle.
    var restThreshold: Double
    private(set) var isSettled: Bool

    init(_ value: Double, parameters: SpringParameters = .smooth, restThreshold: Double = 0.001) {
        self.value = value
        self.velocity = 0
        self.target = value
        self.parameters = parameters
        self.restThreshold = restThreshold
        self.isSettled = true
    }

    /// Moves the destination. Value and velocity are preserved for continuity.
    mutating func retarget(_ newTarget: Double, parameters newParameters: SpringParameters? = nil) {
        if let newParameters { parameters = newParameters }
        guard newTarget != target || !isSettled else { return }
        target = newTarget
        isSettled = abs(value - target) < restThreshold && abs(velocity) < restThreshold
        if isSettled { value = target; velocity = 0 }
    }

    /// Jumps to a value with no animation.
    mutating func snap(to newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0
        isSettled = true
    }

    /// Adds momentum (e.g. a little "kick" when content is replaced in place).
    mutating func addImpulse(_ dv: Double) {
        velocity += dv
        isSettled = false
    }

    /// Advances the simulation by `dt` seconds.
    mutating func step(_ dt: Double) {
        guard !isSettled, dt > 0, dt.isFinite else { return }
        let state = SpringSolver.solve(
            displacement: value - target,
            velocity: velocity,
            parameters: parameters,
            time: dt
        )
        value = target + state.displacement
        velocity = state.velocity
        let velocityThreshold = max(restThreshold * 10, 0.01)
        if abs(state.displacement) < restThreshold && abs(velocity) < velocityThreshold {
            value = target
            velocity = 0
            isSettled = true
        }
    }
}

nonisolated enum SpringSolver {
    struct State: Equatable { var displacement: Double; var velocity: Double }

    /// Closed-form solution of x'' + 2ζω₀x' + ω₀²x = 0.
    static func solve(displacement x0: Double, velocity v0: Double, parameters: SpringParameters, time t: Double) -> State {
        let w0 = parameters.angularFrequency
        let zeta = parameters.dampingFraction

        if zeta < 1 {
            let wd = w0 * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * w0 * t)
            let a = x0
            let b = (v0 + zeta * w0 * x0) / wd
            let c = cos(wd * t)
            let s = sin(wd * t)
            let x = decay * (a * c + b * s)
            let v = decay * (v0 * c - (zeta * w0 * v0 + w0 * w0 * x0) / wd * s)
            return State(displacement: x, velocity: v)
        } else if zeta == 1 {
            let decay = exp(-w0 * t)
            let b = v0 + w0 * x0
            return State(displacement: decay * (x0 + b * t), velocity: decay * (v0 - w0 * b * t))
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -w0 * (zeta - root)
            let r2 = -w0 * (zeta + root)
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            return State(displacement: c1 * e1 + c2 * e2, velocity: r1 * c1 * e1 + r2 * c2 * e2)
        }
    }

    /// Approximate time for the spring to come to rest from a unit displacement.
    static func settlingDuration(_ parameters: SpringParameters, epsilon: Double = 0.001) -> Double {
        var spring = SpringValue(1, parameters: parameters, restThreshold: epsilon)
        spring.retarget(0)
        var t = 0.0
        let dt = 1.0 / 120.0
        while !spring.isSettled && t < 10 {
            spring.step(dt)
            t += dt
        }
        return t
    }
}
