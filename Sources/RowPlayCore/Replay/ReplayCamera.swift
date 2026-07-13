import Foundation

/// Renderer-neutral camera choices for the 3D replay.
public enum ReplayCameraPreset: String, CaseIterable, Equatable, Hashable, Sendable {
    case chase
    case side
    case overhead
    case orbit

    public var displayName: String {
        switch self {
        case .chase: "Chase"
        case .side: "Side"
        case .overhead: "Overhead"
        case .orbit: "Orbit"
        }
    }

    public var systemImage: String {
        switch self {
        case .chase: "camera.fill"
        case .side: "rectangle.side.left.inset.filled"
        case .overhead: "arrow.down.to.line.compact"
        case .orbit: "rotate.3d"
        }
    }
}

/// User-controlled orbit values with explicit safe bounds.
public struct ReplayCameraOrbit: Equatable, Sendable {
    public static let minimumPitch = 10.0 * Double.pi / 180.0
    public static let maximumPitch = 75.0 * Double.pi / 180.0
    public static let minimumDistance = 4.0
    public static let maximumDistance = 30.0
    public static let defaultPitch = 28.0 * Double.pi / 180.0
    public static let defaultDistance = 10.0

    public private(set) var yaw: Double
    public private(set) var pitch: Double
    public private(set) var distance: Double

    public init(
        yaw: Double = 0,
        pitch: Double = ReplayCameraOrbit.defaultPitch,
        distance: Double = ReplayCameraOrbit.defaultDistance
    ) {
        self.yaw = Self.normalizedYaw(yaw)
        self.pitch = Self.clampedPitch(pitch)
        self.distance = Self.clampedDistance(distance)
    }

    public mutating func rotate(yawDelta: Double, pitchDelta: Double) {
        let safeYawDelta = yawDelta.isFinite ? yawDelta : 0
        let safePitchDelta = pitchDelta.isFinite ? pitchDelta : 0
        yaw = Self.normalizedYaw(yaw + safeYawDelta)
        pitch = Self.clampedPitch(pitch + safePitchDelta)
    }

    public mutating func zoom(magnification: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        distance = Self.clampedDistance(distance / magnification)
    }

    public mutating func reset() {
        self = ReplayCameraOrbit()
    }

    private static func normalizedYaw(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let tau = Double.pi * 2
        var result = value.remainder(dividingBy: tau)
        if result > Double.pi {
            result -= tau
        } else if result < -Double.pi {
            result += tau
        }
        return result
    }

    private static func clampedPitch(_ value: Double) -> Double {
        let safe = value.isFinite ? value : defaultPitch
        return min(maximumPitch, max(minimumPitch, safe))
    }

    private static func clampedDistance(_ value: Double) -> Double {
        let safe = value.isFinite ? value : defaultDistance
        return min(maximumDistance, max(minimumDistance, safe))
    }
}

/// A portable camera transform. RealityKit conversion happens in RowPlayStudio.
public struct ReplayCameraPose: Equatable, Sendable {
    public let positionX: Double
    public let positionY: Double
    public let positionZ: Double
    public let targetX: Double
    public let targetY: Double
    public let targetZ: Double
    public let fieldOfViewDegrees: Double
    /// True when construction repaired a non-finite coordinate or an
    /// out-of-range field of view. Keeping this public makes validity part of
    /// the value rather than hidden provenance that would violate Equatable.
    public let wasSanitized: Bool

    public init(
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        targetX: Double,
        targetY: Double,
        targetZ: Double,
        fieldOfViewDegrees: Double
    ) {
        wasSanitized = !positionX.isFinite
            || !positionY.isFinite
            || !positionZ.isFinite
            || !targetX.isFinite
            || !targetY.isFinite
            || !targetZ.isFinite
            || !fieldOfViewDegrees.isFinite
            || fieldOfViewDegrees < 46
            || fieldOfViewDegrees > 51
        self.positionX = positionX.isFinite ? positionX : 0
        self.positionY = positionY.isFinite ? positionY : 3.6
        self.positionZ = positionZ.isFinite ? positionZ : -5.8
        self.targetX = targetX.isFinite ? targetX : 4.4
        self.targetY = targetY.isFinite ? targetY : 0.85
        self.targetZ = targetZ.isFinite ? targetZ : 0
        self.fieldOfViewDegrees = min(
            51,
            max(46, fieldOfViewDegrees.isFinite ? fieldOfViewDegrees : 46)
        )
    }

    public var isFinite: Bool {
        positionX.isFinite && positionY.isFinite && positionZ.isFinite
            && targetX.isFinite && targetY.isFinite && targetZ.isFinite
            && fieldOfViewDegrees.isFinite
    }

    public static let fallback = ReplayCameraPose(
        positionX: -5.8,
        positionY: 3.6,
        positionZ: 0,
        targetX: 4.4,
        targetY: 0.85,
        targetZ: 0,
        fieldOfViewDegrees: 46
    )

    fileprivate func withFixedFieldOfView() -> ReplayCameraPose {
        ReplayCameraPose(
            positionX: positionX,
            positionY: positionY,
            positionZ: positionZ,
            targetX: targetX,
            targetY: targetY,
            targetZ: targetZ,
            fieldOfViewDegrees: 46
        )
    }

    fileprivate func validated(fallback: ReplayCameraPose = .fallback) -> ReplayCameraPose {
        wasSanitized || !isFinite ? fallback : self
    }
}

/// Deterministic, renderer-neutral camera target and smoothing solver.
public enum ReplayCameraSolver: Sendable {
    public static let positionDampingRate = 7.5
    public static let fieldOfViewDampingRate = 2.5

    public static func targetPose(
        preset: ReplayCameraPreset,
        participant: ReplayPosition,
        tangent: ReplayPosition,
        speed: Double,
        orbit: ReplayCameraOrbit = ReplayCameraOrbit(),
        reduceMotion: Bool = false
    ) -> ReplayCameraPose {
        let px = finite(participant.x, fallback: 0)
        let py = finite(participant.y, fallback: 0)
        let pz = finite(participant.z, fallback: 0)
        let direction = normalizedHorizontal(x: tangent.x, z: tangent.z, fallbackX: 1, fallbackZ: 0)
        let rightX = -direction.z
        let rightZ = direction.x
        let radial = normalizedHorizontal(
            x: px,
            z: pz,
            fallbackX: rightX,
            fallbackZ: rightZ
        )

        let pose: ReplayCameraPose
        switch preset {
        case .chase:
            let replaySpeed = speed.isFinite ? max(0, speed) : 0
            let speedFraction = min(1, max(0, (replaySpeed - 3) / 6))
            pose = ReplayCameraPose(
                positionX: px - direction.x * 5.8 + radial.x * 1.1,
                positionY: py + 3.6,
                positionZ: pz - direction.z * 5.8 + radial.z * 1.1,
                targetX: px + direction.x * 4.4,
                targetY: py + 0.85,
                targetZ: pz + direction.z * 4.4,
                fieldOfViewDegrees: 46 + speedFraction * 5
            )
        case .side:
            pose = ReplayCameraPose(
                positionX: px + rightX * 9,
                positionY: py + 2.8,
                positionZ: pz + rightZ * 9,
                targetX: px,
                targetY: py + 0.9,
                targetZ: pz,
                fieldOfViewDegrees: 46
            )
        case .overhead:
            pose = ReplayCameraPose(
                positionX: px - direction.x * 2,
                positionY: py + 18,
                positionZ: pz - direction.z * 2,
                targetX: px,
                targetY: py + 0.5,
                targetZ: pz,
                fieldOfViewDegrees: 46
            )
        case .orbit:
            let horizontalDistance = orbit.distance * cos(orbit.pitch)
            let backX = -direction.x * cos(orbit.yaw) + rightX * sin(orbit.yaw)
            let backZ = -direction.z * cos(orbit.yaw) + rightZ * sin(orbit.yaw)
            pose = ReplayCameraPose(
                positionX: px + backX * horizontalDistance,
                positionY: py + sin(orbit.pitch) * orbit.distance,
                positionZ: pz + backZ * horizontalDistance,
                targetX: px,
                targetY: py + 0.9,
                targetZ: pz,
                fieldOfViewDegrees: 46
            )
        }

        let safePose = pose.validated()
        return reduceMotion ? safePose.withFixedFieldOfView() : safePose
    }

    public static func smoothedPose(
        current: ReplayCameraPose,
        target: ReplayCameraPose,
        dt: Double,
        reduceMotion: Bool = false,
        positionRate: Double = positionDampingRate,
        fieldOfViewRate: Double = fieldOfViewDampingRate
    ) -> ReplayCameraPose {
        let safeTarget = target.validated()
        if current.wasSanitized || !current.isFinite {
            return reduceMotion ? safeTarget.withFixedFieldOfView() : safeTarget
        }
        if reduceMotion {
            return safeTarget.withFixedFieldOfView()
        }

        let safeDt = dt.isFinite ? max(0, dt) : 0
        let safePositionRate = positionRate.isFinite ? max(0, positionRate) : positionDampingRate
        let safeFieldOfViewRate = fieldOfViewRate.isFinite
            ? max(0, fieldOfViewRate)
            : fieldOfViewDampingRate
        let positionFactor = clampUnit(ReplayMotion.dampFactor(rate: safePositionRate, dt: safeDt))
        let fieldOfViewFactor = clampUnit(
            ReplayMotion.dampFactor(rate: safeFieldOfViewRate, dt: safeDt)
        )

        return ReplayCameraPose(
            positionX: damp(current.positionX, safeTarget.positionX, factor: positionFactor),
            positionY: damp(current.positionY, safeTarget.positionY, factor: positionFactor),
            positionZ: damp(current.positionZ, safeTarget.positionZ, factor: positionFactor),
            targetX: damp(current.targetX, safeTarget.targetX, factor: positionFactor),
            targetY: damp(current.targetY, safeTarget.targetY, factor: positionFactor),
            targetZ: damp(current.targetZ, safeTarget.targetZ, factor: positionFactor),
            fieldOfViewDegrees: damp(
                current.fieldOfViewDegrees,
                safeTarget.fieldOfViewDegrees,
                factor: fieldOfViewFactor
            )
        ).validated(fallback: safeTarget)
    }

    private static func normalizedHorizontal(
        x: Double,
        z: Double,
        fallbackX: Double,
        fallbackZ: Double
    ) -> (x: Double, z: Double) {
        let safeX = finite(x, fallback: 0)
        let safeZ = finite(z, fallback: 0)
        let length = hypot(safeX, safeZ)
        guard length.isFinite, length > 0.000_001 else {
            return (fallbackX, fallbackZ)
        }
        return (safeX / length, safeZ / length)
    }

    private static func damp(_ current: Double, _ target: Double, factor: Double) -> Double {
        let safeCurrent = finite(current, fallback: target)
        let safeTarget = finite(target, fallback: safeCurrent)
        let delta = safeTarget - safeCurrent
        if delta.isFinite {
            let result = safeCurrent + delta * factor
            return finite(result, fallback: safeTarget)
        }

        // Opposite finite extremes can overflow during subtraction. The weighted
        // form avoids that overflow while preserving the same interpolation.
        let result = safeCurrent * (1 - factor) + safeTarget * factor
        return finite(result, fallback: safeTarget)
    }

    private static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1, max(0, value))
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}
