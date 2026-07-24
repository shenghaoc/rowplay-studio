import Foundation

// MARK: - Common Joint Pose

/// Common torso/head/shoulder/hip/knee/ankle targets shared by all sports.
/// Angles in radians. Positive rotations follow right-hand rule around the
/// joint's local axis.
public struct ReplayAthleteJointPose: Equatable, Sendable {
    /// Torso lean forward (positive) / backward (negative) from vertical.
    public var torsoLean: Double
    /// Torso lateral tilt (positive = right).
    public var torsoTilt: Double
    /// Head pitch (positive = look down).
    public var headPitch: Double
    /// Left shoulder flexion (positive = arm forward).
    public var shoulderFlexL: Double
    /// Right shoulder flexion.
    public var shoulderFlexR: Double
    /// Left elbow flexion (positive = bend).
    public var elbowFlexL: Double
    /// Right elbow flexion.
    public var elbowFlexR: Double
    /// Left hip flexion (positive = knee toward chest).
    public var hipFlexL: Double
    /// Right hip flexion.
    public var hipFlexR: Double
    /// Left knee flexion (positive = bend).
    public var kneeFlexL: Double
    /// Right knee flexion.
    public var kneeFlexR: Double
    /// Left ankle dorsiflexion (positive = toes up).
    public var ankleDorsiL: Double
    /// Right ankle dorsiflexion.
    public var ankleDorsiR: Double

    public init(
        torsoLean: Double = 0,
        torsoTilt: Double = 0,
        headPitch: Double = 0,
        shoulderFlexL: Double = 0,
        shoulderFlexR: Double = 0,
        elbowFlexL: Double = 0,
        elbowFlexR: Double = 0,
        hipFlexL: Double = 0,
        hipFlexR: Double = 0,
        kneeFlexL: Double = 0,
        kneeFlexR: Double = 0,
        ankleDorsiL: Double = 0,
        ankleDorsiR: Double = 0
    ) {
        self.torsoLean = torsoLean
        self.torsoTilt = torsoTilt
        self.headPitch = headPitch
        self.shoulderFlexL = shoulderFlexL
        self.shoulderFlexR = shoulderFlexR
        self.elbowFlexL = elbowFlexL
        self.elbowFlexR = elbowFlexR
        self.hipFlexL = hipFlexL
        self.hipFlexR = hipFlexR
        self.kneeFlexL = kneeFlexL
        self.kneeFlexR = kneeFlexR
        self.ankleDorsiL = ankleDorsiL
        self.ankleDorsiR = ankleDorsiR
    }

    /// Neutral rest pose with all joints at zero.
    public static let neutral = ReplayAthleteJointPose()
}

// MARK: - Sport-Specific Poses

/// RowErg-specific rig pose: seat travel, handle travel, oar sweep/feather,
/// plus the common athlete joints.
public struct ReplayRowerRigPose: Equatable, Sendable {
    /// Common athlete joint angles.
    public var joints: ReplayAthleteJointPose
    /// Seat Z offset from neutral (negative = toward stern/catch).
    public var seatZ: Double
    /// Handle Y position (vertical).
    public var handleY: Double
    /// Handle Z position (forward/back).
    public var handleZ: Double
    /// Handle rotation (recovery feather).
    public var handleRotX: Double
    /// Oar sweep angle (radians, positive = toward bow).
    public var oarSweep: Double
    /// Oar feather angle (radians, Z rotation for blade bury/feather).
    public var oarFeather: Double

    public init(
        joints: ReplayAthleteJointPose = .neutral,
        seatZ: Double = 0,
        handleY: Double = 0,
        handleZ: Double = 0,
        handleRotX: Double = 0,
        oarSweep: Double = 0,
        oarFeather: Double = 0
    ) {
        self.joints = joints
        self.seatZ = seatZ
        self.handleY = handleY
        self.handleZ = handleZ
        self.handleRotX = handleRotX
        self.oarSweep = oarSweep
        self.oarFeather = oarFeather
    }
}

/// SkiErg-specific rig pose: hip compression, handle height, pole travel,
/// plus the common athlete joints.
public struct ReplaySkiErgRigPose: Equatable, Sendable {
    /// Common athlete joint angles.
    public var joints: ReplayAthleteJointPose
    /// Hip compression amount (0 = tall, 1 = fully compressed).
    public var hipCompression: Double
    /// Handle Y position (vertical).
    public var handleY: Double
    /// Handle Z position (forward/back).
    public var handleZ: Double
    /// Pole rotation angle (radians).
    public var poleRotation: Double

    public init(
        joints: ReplayAthleteJointPose = .neutral,
        hipCompression: Double = 0,
        handleY: Double = 0,
        handleZ: Double = 0,
        poleRotation: Double = 0
    ) {
        self.joints = joints
        self.hipCompression = hipCompression
        self.handleY = handleY
        self.handleZ = handleZ
        self.poleRotation = poleRotation
    }
}

/// A 2D pedal position relative to the bottom bracket.
public struct ReplayPedalPosition: Equatable, Sendable {
    public var y: Double
    public var z: Double

    public init(y: Double = 0, z: Double = 0) {
        self.y = y
        self.z = z
    }
}

/// BikeErg-specific rig pose: crank angle, wheel angle, pedal positions,
/// plus the common athlete joints.
public struct ReplayBikeErgRigPose: Equatable, Sendable {
    /// Common athlete joint angles.
    public var joints: ReplayAthleteJointPose
    /// Crank angle in radians (continuous, drives pedal positions).
    public var crankAngle: Double
    /// Wheel rotation in radians (continuous, faster than crank).
    public var wheelAngle: Double
    /// Left pedal position relative to bottom bracket.
    public var pedalPosL: ReplayPedalPosition
    /// Right pedal position relative to bottom bracket.
    public var pedalPosR: ReplayPedalPosition
    /// Rider lateral sway angle (radians).
    public var riderSway: Double

    public init(
        joints: ReplayAthleteJointPose = .neutral,
        crankAngle: Double = 0,
        wheelAngle: Double = 0,
        pedalPosL: ReplayPedalPosition = ReplayPedalPosition(),
        pedalPosR: ReplayPedalPosition = ReplayPedalPosition(),
        riderSway: Double = 0
    ) {
        self.joints = joints
        self.crankAngle = crankAngle
        self.wheelAngle = wheelAngle
        self.pedalPosL = pedalPosL
        self.pedalPosR = pedalPosR
        self.riderSway = riderSway
    }
}

// MARK: - Sport Rig Pose Enum

/// Sport-specific rig pose, wrapping the three sport variants.
public enum ReplaySportRigPose: Equatable, Sendable {
    case rower(ReplayRowerRigPose)
    case skierg(ReplaySkiErgRigPose)
    case bike(ReplayBikeErgRigPose)
}

// MARK: - Rig Pose Solver

/// Pure, deterministic solver that translates a `ReplayStrokePose` and
/// cumulative distance into a `ReplaySportRigPose`. No platform imports.
public enum ReplayRigPoseSolver {
    /// Solve the rig pose for the given sport, stroke pose, distance, and
    /// reduced-motion preference.
    ///
    /// - Parameters:
    ///   - sport: The workout sport.
    ///   - strokePose: The current stroke pose from the replay engine.
    ///   - distance: Cumulative distance in metres, retained by the uniform
    ///     public sport-solver signature; current articulation is phase-driven.
    ///   - reduceMotion: If true, returns a stable neutral pose.
    /// - Returns: A sport-specific rig pose with all values finite and bounded.
    public static func solve(
        sport: Sport,
        strokePose: ReplayStrokePose,
        distance: Double,
        reduceMotion: Bool
    ) -> ReplaySportRigPose {
        if reduceMotion {
            return reducedPose(sport: sport)
        }
        switch sport {
        case .rower:
            return .rower(solveRower(strokePose: strokePose))
        case .skierg:
            return .skierg(solveSkiErg(strokePose: strokePose))
        case .bike:
            return .bike(solveBikeErg(strokePose: strokePose, distance: distance))
        }
    }

    // MARK: - RowErg Solver

    private static func solveRower(strokePose: ReplayStrokePose) -> ReplayRowerRigPose {
        let graph = ReplayMotionGraph.sampleRower(pose: strokePose)
        let legs = unit(graph.body.legExtension.value)
        let torso = unit(graph.body.spineHinge.value)
        let arms = unit(graph.body.armDraw.value)
        let handle = unit(graph.body.handleTravel.value)
        let feather = unit(graph.contacts.bladeFeather.value)

        // All phase sequencing is carried by `ReplayMotionGraph`. These are
        // static rig-space calibration ranges, not another movement model.
        let seatZ = -0.20 + legs * 0.40
        let handleY = 0.62 - handle * 0.05 + feather * 0.03
        let handleZ = 0.66 - handle * 0.22
        let handleRotX = feather * 0.20
        let oarSweep = -0.58 + handle * 1.16
        let oarFeather = -0.06 + feather * 0.34
        let torsoLean = -0.28 + torso * 0.46
        let shoulderFlex = -0.22 + arms * 0.34
        let elbowFlex = arms * 0.42
        let hipFlex = (1 - legs) * 0.48
        let kneeFlex = (1 - legs) * 0.82
        let ankleDorsi = (1 - legs) * -0.15

        let joints = ReplayAthleteJointPose(
            torsoLean: finite(torsoLean, fallback: 0),
            torsoTilt: 0,
            headPitch: finite(-torsoLean * 0.3, fallback: 0),
            shoulderFlexL: finite(shoulderFlex, fallback: 0),
            shoulderFlexR: finite(shoulderFlex, fallback: 0),
            elbowFlexL: finite(elbowFlex, fallback: 0),
            elbowFlexR: finite(elbowFlex, fallback: 0),
            hipFlexL: finite(hipFlex, fallback: 0),
            hipFlexR: finite(hipFlex, fallback: 0),
            kneeFlexL: finite(kneeFlex, fallback: 0),
            kneeFlexR: finite(kneeFlex, fallback: 0),
            ankleDorsiL: finite(ankleDorsi, fallback: 0),
            ankleDorsiR: finite(ankleDorsi, fallback: 0)
        )

        return ReplayRowerRigPose(
            joints: joints,
            seatZ: finite(seatZ, fallback: -0.1),
            handleY: finite(handleY, fallback: 0.72),
            handleZ: finite(handleZ, fallback: 0.58),
            handleRotX: finite(handleRotX, fallback: 0),
            oarSweep: finite(oarSweep, fallback: 0),
            oarFeather: finite(oarFeather, fallback: -0.06)
        )
    }

    // MARK: - SkiErg Solver

    private static func solveSkiErg(strokePose: ReplayStrokePose) -> ReplaySkiErgRigPose {
        let graph = ReplayMotionGraph.sampleSkier(pose: strokePose)
        let press = unit(graph.body.armPress.value)
        let hinge = unit(graph.body.pelvisHinge.value)
        let knees = unit(graph.body.kneeFlex.value)
        let elbow = unit(graph.body.elbowLoad.value)
        let poleSweep = unit(graph.body.poleSweep.value)
        let armExtension = unit(graph.body.armExtension.value)
        let hipCompression = unit(graph.body.torsoCompression.value)
        let torsoLean = 0.18 + hinge * 0.55
        let handleY = 0.82 - press * 0.42
        let handleZ = 0.28 - poleSweep * 0.38
        let poleRotation = -0.20 - poleSweep * 0.92
        let shoulderFlex = 0.26 - press * 0.64
        let elbowFlex = elbow * 0.55 + (1 - armExtension) * 0.16
        let legFlex = knees * 0.24

        let joints = ReplayAthleteJointPose(
            torsoLean: finite(torsoLean, fallback: 0.2),
            torsoTilt: 0,
            headPitch: finite(torsoLean * 0.2, fallback: 0),
            shoulderFlexL: finite(shoulderFlex, fallback: 0),
            shoulderFlexR: finite(shoulderFlex, fallback: 0),
            elbowFlexL: finite(elbowFlex, fallback: 0),
            elbowFlexR: finite(elbowFlex, fallback: 0),
            hipFlexL: finite(legFlex, fallback: 0),
            hipFlexR: finite(legFlex, fallback: 0),
            kneeFlexL: finite(-legFlex * 0.75, fallback: 0),
            kneeFlexR: finite(-legFlex * 0.75, fallback: 0),
            ankleDorsiL: 0,
            ankleDorsiR: 0
        )

        return ReplaySkiErgRigPose(
            joints: joints,
            hipCompression: finite(hipCompression, fallback: 0),
            handleY: finite(handleY, fallback: 0.42),
            handleZ: finite(handleZ, fallback: 0.16),
            poleRotation: finite(poleRotation, fallback: -0.1)
        )
    }

    // MARK: - BikeErg Solver

    private static func solveBikeErg(
        strokePose: ReplayStrokePose,
        distance: Double
    ) -> ReplayBikeErgRigPose {
        let graph = ReplayMotionGraph.sampleBike(pose: strokePose)
        let crankAngle = graph.crank.angle
        // Mirrors merged `renderer3d.ts`: wheels advance from course distance,
        // while crank/pedal timing comes from the graph's circular state.
        let wheelAngle = finite(distance, fallback: 0) / 0.45
        let crankRadius: Double = 0.18
        let cosCrank = graph.leftPedal.rotation.cos
        let sinCrank = graph.leftPedal.rotation.sin
        let pedalYL = crankRadius * cosCrank
        let pedalZL = crankRadius * sinCrank
        let pedalYR = -pedalYL
        let pedalZR = -pedalZL
        let riderSway = graph.body.torsoSway.value * 0.15
        let thighAngleL = atan2(pedalZL + 0.35, 0.8 - pedalYL)
        let thighAngleR = atan2(pedalZR + 0.35, 0.8 - pedalYR)
        let leftKnee = unit(graph.leftPedal.kneeLift.value)
        let rightKnee = unit(graph.rightPedal.kneeLift.value)

        let joints = ReplayAthleteJointPose(
            torsoLean: finite(0.74 + graph.body.spineLean.value, fallback: 0.74),
            torsoTilt: finite(riderSway, fallback: 0),
            headPitch: finite(0.1 + graph.body.headStabilization.value, fallback: 0.1),
            shoulderFlexL: finite(-0.3 + graph.body.shoulderCounterRotation.value, fallback: -0.3),
            shoulderFlexR: finite(-0.3 - graph.body.shoulderCounterRotation.value, fallback: -0.3),
            elbowFlexL: 0.4,
            elbowFlexR: 0.4,
            hipFlexL: finite(thighAngleL, fallback: 0),
            hipFlexR: finite(thighAngleR, fallback: 0),
            kneeFlexL: finite(leftKnee * 0.8, fallback: 0),
            kneeFlexR: finite(rightKnee * 0.8, fallback: 0),
            ankleDorsiL: finite(graph.leftPedal.ankleFlex.value * 0.3, fallback: 0),
            ankleDorsiR: finite(graph.rightPedal.ankleFlex.value * 0.3, fallback: 0)
        )

        return ReplayBikeErgRigPose(
            joints: joints,
            crankAngle: finite(crankAngle, fallback: 0),
            wheelAngle: finite(wheelAngle, fallback: 0),
            pedalPosL: ReplayPedalPosition(y: finite(pedalYL, fallback: 0), z: finite(pedalZL, fallback: 0)),
            pedalPosR: ReplayPedalPosition(y: finite(pedalYR, fallback: 0), z: finite(pedalZR, fallback: 0)),
            riderSway: finite(riderSway, fallback: 0)
        )
    }

    // MARK: - Reduced Motion

    private static func reducedPose(sport: Sport) -> ReplaySportRigPose {
        switch sport {
        case .rower:
            return .rower(ReplayRowerRigPose(
                joints: .neutral,
                seatZ: -0.1,
                handleY: 0.72,
                handleZ: 0.58,
                handleRotX: 0,
                oarSweep: 0,
                oarFeather: -0.06
            ))
        case .skierg:
            return .skierg(ReplaySkiErgRigPose(
                joints: ReplayAthleteJointPose(
                    torsoLean: 0.2,
                    shoulderFlexL: 0,
                    shoulderFlexR: 0,
                    hipFlexL: 0.08,
                    hipFlexR: 0.08,
                    kneeFlexL: -0.05,
                    kneeFlexR: -0.05
                ),
                hipCompression: 0,
                handleY: 0.42,
                handleZ: 0.16,
                poleRotation: -0.2
            ))
        case .bike:
            return .bike(ReplayBikeErgRigPose(
                joints: ReplayAthleteJointPose(
                    torsoLean: 0.74,
                    shoulderFlexL: -0.3,
                    shoulderFlexR: -0.3,
                    elbowFlexL: 0.4,
                    elbowFlexR: 0.4
                ),
                crankAngle: 0,
                wheelAngle: 0,
                pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
                pedalPosR: ReplayPedalPosition(y: -0.18, z: 0),
                riderSway: 0
            ))
        }
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0
    }
}

// MARK: - Private Helpers

/// Returns `v` if finite, otherwise `fallback`. Shared across Core replay files.
func finite(_ v: Double, fallback: Double) -> Double {
    v.isFinite ? v : fallback
}
