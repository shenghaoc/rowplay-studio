import Foundation

/// Result of a two-bone solve.  `end` is clamped to the reachable annulus if
/// the requested target cannot be reached with the declared segment lengths.
public struct ReplayTwoBoneSolution: Equatable, Sendable {
    public let joint: SIMD3<Double>
    public let end: SIMD3<Double>

    public init(joint: SIMD3<Double>, end: SIMD3<Double>) {
        self.joint = joint
        self.end = end
    }
}

/// Fixed-length two-bone and rigid-contact solvers ported from RowPlay V4
/// `figurePose.ts`.  They have no rendering dependencies and deliberately use
/// deterministic fallback planes so a seek or phase wrap cannot flip knees or
/// elbows.
public enum ReplayTwoBoneSolver {
    public static let epsilon = 1e-9

    public static func solve2D(
        root: SIMD2<Double>,
        target: SIMD2<Double>,
        firstLength: Double,
        secondLength: Double,
        bendDirection: Double
    ) -> (joint: SIMD2<Double>, end: SIMD2<Double>) {
        let root = finite(root)
        let target = finite(target)
        let first = segmentLength(firstLength)
        let second = segmentLength(secondLength)
        let delta = target - root
        let distance = length(delta)
        let bend = bendDirection.isFinite && bendDirection < 0 ? -1.0 : 1.0

        guard first + second > epsilon else {
            return (root, root)
        }
        if distance <= epsilon && abs(first - second) <= epsilon {
            return (SIMD2(root.x, root.y + first * bend), root)
        }
        let direction: SIMD2<Double>
        if distance > epsilon {
            direction = delta / distance
        } else {
            direction = SIMD2(1, 0)
        }
        guard direction.x.isFinite && direction.y.isFinite else {
            return (SIMD2(root.x, root.y + first), SIMD2(root.x, root.y + first + second))
        }
        let solveDistance = clampedReach(distance, first, second)
        let end = solveDistance == distance ? target : root + direction * solveDistance
        let safeDistance = max(epsilon, solveDistance)
        let along = (first * first - second * second + safeDistance * safeDistance) / (2 * safeDistance)
        let perpendicular = sqrt(max(0, first * first - along * along))
        let joint = SIMD2(
            root.x + direction.x * along - direction.y * perpendicular * bend,
            root.y + direction.y * along + direction.x * perpendicular * bend
        )
        return (finite(joint), finite(end))
    }

    public static func solve3D(
        root: SIMD3<Double>,
        target: SIMD3<Double>,
        firstLength: Double,
        secondLength: Double,
        bendHint: SIMD3<Double>
    ) -> ReplayTwoBoneSolution {
        let root = finite(root)
        let target = finite(target)
        let first = segmentLength(firstLength)
        let second = segmentLength(secondLength)
        let delta = target - root
        let distance = length(delta)

        guard first + second > epsilon else {
            return ReplayTwoBoneSolution(joint: root, end: root)
        }

        let candidateDirection = distance > epsilon ? delta / distance : SIMD3<Double>(1, 0, 0)
        let direction: SIMD3<Double>
        if candidateDirection.x.isFinite,
           candidateDirection.y.isFinite,
           candidateDirection.z.isFinite {
            direction = candidateDirection
        } else {
            // Finite coordinates near Double.max can overflow during the
            // subtraction/hypotenuse step. Use the same deterministic axis
            // fallback as a coincident target rather than manufacture NaNs.
            direction = SIMD3<Double>(1, 0, 0)
        }
        let hint = perpendicularHint(bendHint, to: direction)
        if distance <= epsilon && abs(first - second) <= epsilon {
            return ReplayTwoBoneSolution(joint: root + hint * first, end: root)
        }

        let solveDistance = clampedReach(distance, first, second)
        let end = solveDistance == distance ? target : root + direction * solveDistance
        let safeDistance = max(epsilon, solveDistance)
        let along = (first * first - second * second + safeDistance * safeDistance) / (2 * safeDistance)
        let perpendicular = sqrt(max(0, first * first - along * along))
        return ReplayTwoBoneSolution(
            joint: finite(root + direction * along + hint * perpendicular),
            end: finite(end)
        )
    }

    /// Solve the point closest to `preferred` on a rigid contact sphere while
    /// keeping it inside a root reach annulus.  A `false` result means the two
    /// constraints do not intersect; the returned point still preserves the
    /// rigid contact radius and minimizes the arm residual deterministically.
    public static func solveRigidContact3D(
        root: SIMD3<Double>,
        preferred: SIMD3<Double>,
        contactCenter: SIMD3<Double>,
        contactLength: Double,
        minimumReach: Double,
        maximumReach: Double
    ) -> (point: SIMD3<Double>, isFeasible: Bool) {
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
            preferredDirection = SIMD3(1, 0, 0)
            preferredLength = 1
        }
        let candidate = center + preferredDirection * (radius / preferredLength)
        let candidateReach = length(candidate - root)
        if candidateReach >= minimum - epsilon && candidateReach <= maximum + epsilon {
            return (finite(candidate), true)
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
            let circleCenter = center + rootDelta * along
            let circleRadius = sqrt(max(0, radius * radius - along * along))
            let planeDirection = perpendicularHint(preferred - circleCenter, to: rootDelta)
            return (finite(circleCenter + planeDirection * circleRadius), true)
        }

        if centerDistance > epsilon {
            return (finite(center + rootDelta * (radius / centerDistance)), false)
        }
        return (finite(center + preferredDirection * (radius / preferredLength)), false)
    }

    private static func clampedReach(_ distance: Double, _ first: Double, _ second: Double) -> Double {
        max(abs(first - second), min(first + second, distance))
    }

    private static func segmentLength(_ value: Double) -> Double {
        value.isFinite ? max(0, abs(value)) : 0
    }

    private static func perpendicularHint(_ rawHint: SIMD3<Double>, to direction: SIMD3<Double>) -> SIMD3<Double> {
        var hint = finite(rawHint)
        hint -= direction * dot(hint, direction)
        var hintLength = length(hint)
        if hintLength <= epsilon {
            let absDirection = SIMD3(abs(direction.x), abs(direction.y), abs(direction.z))
            let axis: SIMD3<Double>
            if absDirection.x <= absDirection.y && absDirection.x <= absDirection.z {
                axis = SIMD3(1, 0, 0)
            } else if absDirection.y <= absDirection.z {
                axis = SIMD3(0, 1, 0)
            } else {
                axis = SIMD3(0, 0, 1)
            }
            hint = axis - direction * dot(axis, direction)
            hintLength = length(hint)
        }
        guard hintLength > epsilon, hintLength.isFinite else {
            return SIMD3(0, 1, 0)
        }
        return hint / hintLength
    }

    private static func finite(_ value: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func finite(_ value: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0,
            value.z.isFinite ? value.z : 0
        )
    }

    private static func dot(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        first.x * second.x + first.y * second.y + first.z * second.z
    }

    private static func length(_ value: SIMD2<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y)
    }

    private static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }
}
