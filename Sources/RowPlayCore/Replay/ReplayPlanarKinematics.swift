import Foundation

/// Rendering-independent 2D limb solve with scalar conveniences for Canvas
/// adapters. The requested end is clamped to the two-bone reach annulus.
public struct ReplayPlanarLimbSolution: Equatable, Sendable {
    public let joint: SIMD2<Double>
    public let end: SIMD2<Double>

    public init(joint: SIMD2<Double>, end: SIMD2<Double>) {
        self.joint = joint
        self.end = end
    }

    public var jointX: Double { joint.x }
    public var jointY: Double { joint.y }
    public var endX: Double { end.x }
    public var endY: Double { end.y }
}

/// Point on a rigid contact circle that is also reachable by a two-link limb.
public struct ReplayPlanarRigidContactSolution: Equatable, Sendable {
    public let point: SIMD2<Double>
    public let isFeasible: Bool

    public init(point: SIMD2<Double>, isFeasible: Bool) {
        self.point = point
        self.isFeasible = isFeasible
    }

    public var x: Double { point.x }
    public var y: Double { point.y }
}

/// Portable counterpart of the web `solveRigidContactPoint2D`. It preserves
/// the declared contact radius even when the reach annulus cannot intersect it.
public enum ReplayPlanarRigidContactSolver {
    public static func solve(
        root: SIMD2<Double>,
        preferred: SIMD2<Double>,
        contactCenter: SIMD2<Double>,
        contactLength: Double,
        minimumReach: Double,
        maximumReach: Double
    ) -> ReplayPlanarRigidContactSolution {
        let epsilon = ReplayTwoBoneSolver.epsilon
        let root = finite(root)
        let center = finite(contactCenter)
        let preferred = finite(preferred)
        let radius = segmentLength(contactLength)
        let reachA = segmentLength(minimumReach)
        let reachB = segmentLength(maximumReach)
        let minimum = min(reachA, reachB)
        let maximum = max(reachA, reachB)

        var preferredDirection = preferred - center
        var preferredLength = length(preferredDirection)
        if preferredLength <= epsilon {
            preferredDirection = root - center
            preferredLength = length(preferredDirection)
        }
        if preferredLength <= epsilon {
            preferredDirection = SIMD2(1, 0)
            preferredLength = 1
        }

        let candidate = center + preferredDirection * (radius / preferredLength)
        let candidateReach = length(candidate - root)
        if candidateReach >= minimum - epsilon && candidateReach <= maximum + epsilon {
            return ReplayPlanarRigidContactSolution(point: finite(candidate), isFeasible: true)
        }

        let boundary = candidateReach > maximum ? maximum : minimum
        var rootDelta = root - center
        let centerDistance = length(rootDelta)
        let intersects = centerDistance > epsilon
            && centerDistance <= radius + boundary + epsilon
            && centerDistance + min(radius, boundary) + epsilon >= max(radius, boundary)
        if intersects {
            rootDelta /= centerDistance
            let along = (radius * radius - boundary * boundary + centerDistance * centerDistance)
                / (2 * centerDistance)
            let chordCenter = center + rootDelta * along
            let halfChord = sqrt(max(0, radius * radius - along * along))
            let perpendicular = SIMD2(-rootDelta.y, rootDelta.x) * halfChord
            let positive = chordCenter + perpendicular
            let negative = chordCenter - perpendicular
            let selected = squaredDistance(positive, preferred) <= squaredDistance(negative, preferred)
                ? positive
                : negative
            return ReplayPlanarRigidContactSolution(point: finite(selected), isFeasible: true)
        }

        if centerDistance > epsilon {
            let nearest = center + rootDelta * (radius / centerDistance)
            return ReplayPlanarRigidContactSolution(point: finite(nearest), isFeasible: false)
        }
        let fallback = center + preferredDirection * (radius / preferredLength)
        return ReplayPlanarRigidContactSolution(point: finite(fallback), isFeasible: false)
    }

    private static func finite(_ value: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func segmentLength(_ value: Double) -> Double {
        value.isFinite ? max(0, abs(value)) : 0
    }

    private static func squaredDistance(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        let delta = first - second
        return delta.x * delta.x + delta.y * delta.y
    }

    private static func length(_ value: SIMD2<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y)
    }
}

/// One straight planar oar resolved from handle through lock to blade tip.
public struct ReplayPlanarRigidOar: Equatable, Sendable {
    public let handle: SIMD2<Double>
    public let bladeRoot: SIMD2<Double>
    public let bladeTip: SIMD2<Double>

    public init(handle: SIMD2<Double>, bladeRoot: SIMD2<Double>, bladeTip: SIMD2<Double>) {
        self.handle = handle
        self.bladeRoot = bladeRoot
        self.bladeTip = bladeTip
    }

    public var handleX: Double { handle.x }
    public var handleY: Double { handle.y }
    public var bladeRootX: Double { bladeRoot.x }
    public var bladeRootY: Double { bladeRoot.y }
    public var bladeTipX: Double { bladeTip.x }
    public var bladeTipY: Double { bladeTip.y }
}

/// Side-profile rowing constraints shared by renderers and Linux-safe tests.
public enum ReplayPlanarRowSolver {
    /// Select the rearward (-x) branch of a two-bone rowing arm.
    public static func solveRearwardElbow(
        shoulder: SIMD2<Double>,
        hand: SIMD2<Double>,
        upperArmLength: Double,
        forearmLength: Double
    ) -> ReplayPlanarLimbSolution {
        let primary = ReplayTwoBoneSolver.solve2D(
            root: shoulder,
            target: hand,
            firstLength: upperArmLength,
            secondLength: forearmLength,
            bendDirection: 1
        )
        let alternate = ReplayTwoBoneSolver.solve2D(
            root: shoulder,
            target: hand,
            firstLength: upperArmLength,
            secondLength: forearmLength,
            bendDirection: -1
        )
        let selectedJoint = alternate.joint.x < primary.joint.x
            ? alternate.joint
            : primary.joint
        return ReplayPlanarLimbSolution(joint: selectedJoint, end: primary.end)
    }

    /// Resolve the continuous inboard-circle branch that meets an arm reach.
    public static func solveOarAngle(
        shoulder: SIMD2<Double>,
        lock: SIMD2<Double>,
        inboardLength: Double,
        requestedReach: Double,
        preferredAngle: Double
    ) -> Double {
        let shoulder = finite(shoulder)
        let lock = finite(lock)
        let preferred = preferredAngle.isFinite ? preferredAngle : 0
        let inboardLength = inboardLength.isFinite ? max(0, abs(inboardLength)) : 0
        let requestedReach = requestedReach.isFinite ? max(0, abs(requestedReach)) : 0
        let pinDelta = lock - shoulder
        let amplitude = length(pinDelta)
        guard amplitude >= ReplayTwoBoneSolver.epsilon,
              inboardLength >= ReplayTwoBoneSolver.epsilon else {
            return preferred
        }
        let signedInboard = -inboardLength
        let baseDistanceSquared = dot(pinDelta, pinDelta) + signedInboard * signedInboard
        let cosine = max(
            -1,
            min(
                1,
                (requestedReach * requestedReach - baseDistanceSquared)
                    / (2 * signedInboard * amplitude)
            )
        )
        return atan2(pinDelta.y, pinDelta.x) + acos(cosine)
    }

    public static func solveRigidOar(
        lock: SIMD2<Double>,
        angle: Double,
        inboardLength: Double,
        outboardLength: Double,
        bladeLength: Double
    ) -> ReplayPlanarRigidOar {
        let lock = finite(lock)
        let angle = angle.isFinite ? angle : 0
        let inboard = segmentLength(inboardLength)
        let outboard = segmentLength(outboardLength)
        let blade = segmentLength(bladeLength)
        let direction = SIMD2(cos(angle), sin(angle))
        let handle = lock - direction * inboard
        let bladeRoot = lock + direction * outboard
        return ReplayPlanarRigidOar(
            handle: handle,
            bladeRoot: bladeRoot,
            bladeTip: bladeRoot + direction * blade
        )
    }

    public static func interpolateAngle(from: Double, to: Double, amount: Double) -> Double {
        let from = from.isFinite ? from : 0
        let to = to.isFinite ? to : from
        let amount = amount.isFinite ? amount : 0
        return from + atan2(sin(to - from), cos(to - from)) * amount
    }

    private static func segmentLength(_ value: Double) -> Double {
        value.isFinite ? max(0, abs(value)) : 0
    }

    private static func finite(_ value: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func dot(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        first.x * second.x + first.y * second.y
    }

    private static func length(_ value: SIMD2<Double>) -> Double {
        sqrt(dot(value, value))
    }
}
