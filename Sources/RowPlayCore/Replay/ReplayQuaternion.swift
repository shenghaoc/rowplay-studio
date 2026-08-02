import Foundation

/// Portable unit-quaternion math for the replay motion and grip systems.
///
/// RowPlayCore cannot import Apple's `simd` module (Linux CI builds the Core
/// graph), so this is a minimal, allocation-free value type covering exactly
/// the operations the ported RowPlay math needs: axis-angle construction,
/// Hamilton products, vector rotation, shortest-arc alignment, and normalized
/// shortest-path interpolation for motion-table sampling.
public struct ReplayQuaternion: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public static let identity = ReplayQuaternion(x: 0, y: 0, z: 0, w: 1)

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(axis: SIMD3<Double>, angle: Double) {
        let lengthSquared = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z
        guard lengthSquared > 1e-24, angle.isFinite else {
            self = .identity
            return
        }
        let inverseLength = 1 / lengthSquared.squareRoot()
        let half = angle / 2
        let sine = sin(half)
        x = axis.x * inverseLength * sine
        y = axis.y * inverseLength * sine
        z = axis.z * inverseLength * sine
        w = cos(half)
    }

    /// Shortest-arc rotation sending unit vector `from` onto unit vector `to`.
    /// The 180° case picks a deterministic perpendicular axis.
    public init(from: SIMD3<Double>, to: SIMD3<Double>) {
        let dot = from.x * to.x + from.y * to.y + from.z * to.z
        if dot < -0.999999 {
            var axis = SIMD3<Double>(0, 0, 0)
            if abs(from.x) < 0.9 {
                axis = SIMD3(0, -from.z, from.y)
            } else {
                axis = SIMD3(-from.y, from.x, 0)
            }
            self.init(axis: axis, angle: .pi)
            return
        }
        let cross = SIMD3(
            from.y * to.z - from.z * to.y,
            from.z * to.x - from.x * to.z,
            from.x * to.y - from.y * to.x
        )
        self.init(x: cross.x, y: cross.y, z: cross.z, w: 1 + dot)
        self = normalized()
    }

    public var lengthSquared: Double {
        x * x + y * y + z * z + w * w
    }

    public func normalized() -> ReplayQuaternion {
        let lengthSquared = lengthSquared
        guard lengthSquared > 1e-24, lengthSquared.isFinite else { return .identity }
        let inverseLength = 1 / lengthSquared.squareRoot()
        return ReplayQuaternion(
            x: x * inverseLength,
            y: y * inverseLength,
            z: z * inverseLength,
            w: w * inverseLength
        )
    }

    /// Conjugate; equals the inverse for unit quaternions.
    public func inverted() -> ReplayQuaternion {
        ReplayQuaternion(x: -x, y: -y, z: -z, w: w)
    }

    /// Hamilton product `self * other` (apply `other` first, then `self`).
    public static func * (lhs: ReplayQuaternion, rhs: ReplayQuaternion) -> ReplayQuaternion {
        ReplayQuaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Rotate a vector by this quaternion.
    public func act(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        // v' = v + 2 * cross(q.xyz, cross(q.xyz, v) + w * v)
        let qv = SIMD3(x, y, z)
        let uv = SIMD3(
            qv.y * vector.z - qv.z * vector.y,
            qv.z * vector.x - qv.x * vector.z,
            qv.x * vector.y - qv.y * vector.x
        )
        let uuv = SIMD3(
            qv.y * uv.z - qv.z * uv.y,
            qv.z * uv.x - qv.x * uv.z,
            qv.x * uv.y - qv.y * uv.x
        )
        return SIMD3(
            vector.x + 2 * (uv.x * w + uuv.x),
            vector.y + 2 * (uv.y * w + uuv.y),
            vector.z + 2 * (uv.z * w + uuv.z)
        )
    }

    /// Normalized linear interpolation along the shortest path — the motion
    /// table's rotation blend.  nlerp is commutative-safe for the small
    /// per-phase steps a 257-sample clip produces and never spins the long way
    /// around.
    public func interpolated(towards target: ReplayQuaternion, fraction: Double) -> ReplayQuaternion {
        let t = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        var cosine = x * target.x + y * target.y + z * target.z + w * target.w
        var aligned = target
        if cosine < 0 {
            aligned = ReplayQuaternion(x: -target.x, y: -target.y, z: -target.z, w: -target.w)
            cosine = -cosine
        }
        let blended = ReplayQuaternion(
            x: x + (aligned.x - x) * t,
            y: y + (aligned.y - y) * t,
            z: z + (aligned.z - z) * t,
            w: w + (aligned.w - w) * t
        )
        return blended.normalized()
    }
}
