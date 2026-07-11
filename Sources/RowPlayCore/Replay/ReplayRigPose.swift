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
            return .bike(solveBikeErg(strokePose: strokePose))
        }
    }

    // MARK: - RowErg Solver

    private static func solveRower(strokePose: ReplayStrokePose) -> ReplayRowerRigPose {
        let w = strokePose.warpedPhase
        let drive = cos(w)
        let recovery = max(0, -sin(w))
        let amp = strokePose.amplitude

        // Seat slides along rail: compressed toward stern at catch, extended at finish.
        let seatZ = -0.1 - drive * 0.22 * amp

        // Handle moves with stroke.
        let handleY = 0.72 + recovery * 0.04 * amp
        let handleZ = 0.58 - drive * 0.08 * amp
        let handleRotX = recovery * 0.16 * amp

        // Oars sweep and feather.
        let oarSweep = -drive * 0.5 * amp
        let oarFeather = recovery * 0.26 - 0.06

        // Body lean: forward at catch, back at finish.
        let torsoLean = -0.08 - drive * 0.2 * amp

        // Arms: compact at catch (shoulders forward, elbows bent), extended at finish.
        let shoulderFlex = -drive * 0.15 * amp
        let elbowFlex = recovery * 0.3 * amp

        // Legs: compressed at catch (hips flexed, knees bent), extended at finish.
        let hipFlex = drive * 0.35 * amp
        let kneeFlex = drive * 0.5 * amp
        let ankleDorsi = -drive * 0.1 * amp

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
        let w = strokePose.warpedPhase
        let swing = cos(w)
        let crunch = max(0, -swing)
        let amp = strokePose.amplitude

        // Upper body crunch.
        let hipCompression = finite(crunch * amp, fallback: 0)
        let torsoLean = 0.2 + crunch * 0.5 * amp

        // Handles pull down with swing.
        let handleY = 0.42 + swing * 0.16 * amp - crunch * 0.16 * amp
        let handleZ = 0.16 + swing * 0.25 * amp

        // Poles swing.
        let poleRotation = -swing * 0.9 * amp - 0.1

        // Legs flex with crunch.
        let legFlex = crunch * 0.16 * amp

        let joints = ReplayAthleteJointPose(
            torsoLean: finite(torsoLean, fallback: 0.2),
            torsoTilt: 0,
            headPitch: finite(torsoLean * 0.2, fallback: 0),
            shoulderFlexL: finite(-swing * 0.3 * amp, fallback: 0),
            shoulderFlexR: finite(-swing * 0.3 * amp, fallback: 0),
            elbowFlexL: finite(crunch * 0.2 * amp, fallback: 0),
            elbowFlexR: finite(crunch * 0.2 * amp, fallback: 0),
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

    /// Simplified gear ratio: wheel rotation = crank angle × this factor.
    /// Matches the web renderer3d.ts `phase * 2.4` wheel spin formula.
    private static let bikeWheelRatio: Double = 2.4

    private static func solveBikeErg(strokePose: ReplayStrokePose) -> ReplayBikeErgRigPose {
        let phase = strokePose.phase
        let amp = strokePose.amplitude

        // Crank and wheel rotation.
        let crankAngle = finite(phase, fallback: 0)
        let wheelAngle = finite(phase * bikeWheelRatio, fallback: 0)

        // Pedal positions: left and right are 180° apart.
        let crankRadius: Double = 0.18
        let pedalYL = crankRadius * cos(crankAngle)
        let pedalZL = crankRadius * sin(crankAngle)
        let pedalYR = crankRadius * cos(crankAngle + Double.pi)
        let pedalZR = crankRadius * sin(crankAngle + Double.pi)

        // Rider sway with pedal stroke.
        let riderSway = sin(phase) * 0.05 * amp

        // Legs follow pedals: hip stays stable, knee follows pedal position.
        let thighAngleL = atan2(pedalZL + 0.35, 0.8 - pedalYL)
        let thighAngleR = atan2(pedalZR + 0.35, 0.8 - pedalYR)

        let joints = ReplayAthleteJointPose(
            torsoLean: 0.74, // aero tuck
            torsoTilt: finite(riderSway, fallback: 0),
            headPitch: 0.1,
            shoulderFlexL: -0.3,
            shoulderFlexR: -0.3,
            elbowFlexL: 0.4,
            elbowFlexR: 0.4,
            hipFlexL: finite(thighAngleL, fallback: 0),
            hipFlexR: finite(thighAngleR, fallback: 0),
            kneeFlexL: finite(max(0, sin(crankAngle)) * 0.8 * amp, fallback: 0),
            kneeFlexR: finite(max(0, -sin(crankAngle)) * 0.8 * amp, fallback: 0),
            ankleDorsiL: finite(sin(crankAngle) * 0.15, fallback: 0),
            ankleDorsiR: finite(sin(crankAngle + Double.pi) * 0.15, fallback: 0)
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
}

// MARK: - Private Helpers

private func finite(_ v: Double, fallback: Double) -> Double {
    v.isFinite ? v : fallback
}
