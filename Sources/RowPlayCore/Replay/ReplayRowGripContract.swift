import Foundation

/// Rowing-shell rig math ported from RowPlay `rowRig.ts`: the physical
/// contact landmarks of the authored shell, the closed-chain oar-yaw solve,
/// and the down-plane elbow solve.  Kept in Core so the rowing mechanics stay
/// unit testable without a renderer instance.
public enum ReplayRowGripContract {
    public struct FootContact: Sendable {
        public let lateral = 0.12
        public let y = 0.215
        /// Stern-side and directly ahead of the aft-facing athlete.
        public let z = 0.75
    }

    public struct Stretcher: Sendable {
        public let centerY = 0.295
        public let centerZ = 0.68
        public let boardRotation = -48.0 * .pi / 180
        public let shoeCatchPitch = -35.0 * .pi / 180
        public let shoeFinishPitch = -42.0 * .pi / 180
    }

    /// Physical scull-handle contract shared by the rendered rubber and grip
    /// closure.  `anchorFromEnd` places the palm inboard of the flat thumb
    /// stop.
    public struct ScullGrip: Sendable {
        public let radius = 0.023
        public let length = 0.32
        public let anchorFromEnd = 0.04
    }

    public struct Oarlock: Sendable {
        public let lateral = 0.88
        /// The pin rides ~0.14 above the seat top — real sculling rigging
        /// height — and stays below the lower-rib draw.
        public let y = 0.51
        /// Stern-side pin keeps the scull handles in front of the torso at
        /// mid-draw.
        public let z = 0.28
    }

    /// Boat-local rowing elbow corridor (single scull).  Bounds derived from
    /// the shipped rig: shoulder half-width 0.25 m, drawn-elbow circle radius
    /// ≤ 0.27 m, and the 0.18 m torso-core clearance the skinned athlete
    /// needs.
    public struct ElbowCorridor: Sendable {
        /// Maximum outboard displacement of the elbow from the vertical
        /// working plane through the shoulder→wrist chord.
        public let maxOutboard = 0.11
        /// Token inboard excursion across the working plane toward the spine.
        public let maxInboard = 0.05
        /// The joint may trail the shoulder plane, never haul past vertical.
        public let maxBehindShoulder = 0.19
        /// Draw-style guard: ceiling of (outboard excursion)/(rearward
        /// travel) during the loaded draw.  Recalibrated 0.5 → 0.7 with the
        /// flat-wrist sculling grip.
        public let maxOutboardPerRearward = 0.7
    }

    /// Elbow-plane schedule driven by the arm's *actual* flexion.  Near full
    /// extension the elbow circle is a singular, low-authority region.
    public struct ElbowPlane: Sendable {
        /// Flexion (rad from straight) below which the plane has no
        /// authority.
        public let authorityStart = 0.14
        /// Flexion at which the drawn plane owns the joint completely.
        public let authorityFull = 0.55
        /// Relaxed near-straight direction, athlete frame: a soft under-arm
        /// hang with the natural sculling outboard lean.
        public let relaxed = SIMD3<Double>(0.32, -1, -0.12)
        /// Drawn direction, athlete frame — the two-bone branch hint.
        /// Down-and-aft picks the correct branch at every draw chord.
        public let drawn = SIMD3<Double>(0.02, -0.72, -0.69)
        /// Chord-frame station of the drawn elbow on its circle: the outboard
        /// offset scales with the circle radius so 0.24·radius stays a
        /// visible but modest lean.
        public let drawnOutboardWeight = 0.24
        public let drawnDownWeight = (1.0 - 0.24 * 0.24).squareRoot()
    }

    public static let footContact = FootContact()
    public static let stretcher = Stretcher()
    public static let scullGrip = ScullGrip()
    public static let oarlock = Oarlock()
    public static let elbowCorridor = ElbowCorridor()
    public static let elbowPlane = ElbowPlane()

    /// Thumb opposition for the scull grip; the thumb presses the flat
    /// handle-end stop rather than wrapping the shaft.
    public static let scullThumbOppose = 0.3

    /// Grip closure options for one RowErg hand: sequential first-contact
    /// closure around the 23 mm rubber, with the thumb closing axially onto
    /// the flat handle end.
    public static func gripClosureOptions(side: Double) -> ReplayHandGripClosureOptions {
        ReplayHandGripClosureOptions(
            side: side,
            surface: ReplayHandGripSurface(
                radius: scullGrip.radius,
                thumbEndAxial: scullGrip.anchorFromEnd
            ),
            thumbOppose: scullThumbOppose
        )
    }

    /// Arm-draw schedule: the elbow's interior flexion grows linearly with
    /// the motion graph's cruise-shaped armDraw channel, reaching the
    /// measured production finish fold at draw = 1.
    public static let drawFinishFlexion = 2.46

    /// Soft elbow unlock held through the whole drive (radians from
    /// straight): keeps the shoulder→wrist chord away from the straight-arm
    /// singularity, where mm-scale IK settling reads as an elbow pop at draw
    /// onset.
    public static let drawSoftFlexion = 0.32

    /// Choose the continuous yaw branch on a rigid oar's inboard circle that
    /// satisfies a requested shoulder-to-grip reach.  The motion-graph yaw is
    /// used only for a degenerate fallback and the later late-draw blend.
    public static func solveOarYaw(
        shoulder: SIMD3<Double>,
        pinX: Double,
        pinY: Double,
        pinZ: Double,
        signedInboard: Double,
        bladeRoll: Double,
        requestedReach: Double,
        preferredYaw: Double,
        forceReachBoundary: Bool = false
    ) -> Double {
        let pinDeltaX = pinX - shoulder.x
        let pinDeltaY = pinY - shoulder.y
        let pinDeltaZ = pinZ - shoulder.z
        // XYZ Euler order sends an oar-local X vector to
        // (cos(roll)cos(yaw), sin(roll), -cos(roll)sin(yaw)).  Blade burial
        // therefore contributes a yaw-independent vertical term.
        let rollCos = cos(bladeRoll)
        let rollSin = sin(bladeRoll)
        let projectedX = pinDeltaX * rollCos
        let projectedZ = -pinDeltaZ * rollCos
        let amplitude = (projectedX * projectedX + projectedZ * projectedZ).squareRoot()
        if amplitude < 1e-8 || abs(signedInboard) < 1e-8 { return preferredYaw }

        let baseDistanceSquared = pinDeltaX * pinDeltaX
            + pinDeltaY * pinDeltaY
            + pinDeltaZ * pinDeltaZ
            + signedInboard * signedInboard
        let preferredDistanceSquared = baseDistanceSquared
            + 2 * signedInboard
            * (projectedX * cos(preferredYaw)
                + projectedZ * sin(preferredYaw)
                + pinDeltaY * rollSin)
        // Follow the graph-authored oar arc directly whenever the shoulder
        // can reach it; solving only the outer boundary would exchange circle
        // branches exactly when the handle should travel smoothly.
        if !forceReachBoundary,
           preferredDistanceSquared <= requestedReach * requestedReach + 1e-5 {
            return preferredYaw
        }
        let cosine = min(
            max(
                (requestedReach * requestedReach
                    - baseDistanceSquared
                    - 2 * signedInboard * pinDeltaY * rollSin)
                    / (2 * signedInboard * amplitude),
                -1
            ),
            1
        )
        let center = atan2(projectedZ, projectedX)
        let offset = acos(cosine)
        let first = center + offset
        let second = center - offset
        // The catch is the root whose inboard grip sits farther toward the
        // stretcher (+Z): selecting by that physical relationship keeps both
        // mirrored oars forward even when the angular roots exchange
        // numerical closeness.
        let firstGripZ = pinZ - signedInboard * rollCos * sin(first)
        let secondGripZ = pinZ - signedInboard * rollCos * sin(second)
        let selected = firstGripZ >= secondGripZ ? first : second
        // Keep the selected branch equivalent to the staged yaw so the oar
        // never takes a visible ±2π jump across the branch cut.
        return preferredYaw
            + atan2(sin(selected - preferredYaw), cos(selected - preferredYaw))
    }

    /// Shoulder→wrist reach that yields `flexion` for the given segment pair.
    public static func reachForFlexion(
        _ flexion: Double,
        upperArmLength: Double,
        forearmLength: Double
    ) -> Double {
        let clamped = min(max(flexion, 0), .pi - 1e-3)
        return max(
            0,
            upperArmLength * upperArmLength
                + forearmLength * forearmLength
                + 2 * upperArmLength * forearmLength * cos(clamped)
        ).squareRoot()
    }

    /// Elbow flexion (radians away from a straight arm) for a given reach.
    public static func elbowFlexion(
        chordLength: Double,
        upperArmLength: Double,
        forearmLength: Double
    ) -> Double {
        let clamped = min(
            max(chordLength, abs(upperArmLength - forearmLength) + 1e-6),
            upperArmLength + forearmLength - 1e-6
        )
        let cosInterior = (upperArmLength * upperArmLength
            + forearmLength * forearmLength
            - clamped * clamped)
            / (2 * upperArmLength * forearmLength)
        return .pi - acos(min(max(cosInterior, -1), 1))
    }

    /// How much the preferred plane may steer the joint, 0 near straight → 1
    /// once flexion is clearly visible.  C2 (smootherstep).
    public static func elbowPlaneAuthority(_ flexion: Double) -> Double {
        let plane = elbowPlane
        let span = plane.authorityFull - plane.authorityStart
        let unit = min(max((flexion - plane.authorityStart) / span, 0), 1)
        return unit * unit * unit * (unit * (unit * 6 - 15) + 10)
    }

    /// Preferred rowing elbow-plane direction in the athlete frame
    /// (+z stretcher, −z aft draw, +y up, x outboard by side), blended from
    /// the relaxed hang to the aft draw by plane authority.
    public static func elbowPlaneDirection(side: Double, authority: Double) -> SIMD3<Double> {
        let plane = elbowPlane
        let mix = min(max(authority, 0), 1)
        let sign = ReplayGripGeometry.mirrorSign(side)
        let direction = SIMD3(
            sign * (plane.relaxed.x + (plane.drawn.x - plane.relaxed.x) * mix),
            plane.relaxed.y + (plane.drawn.y - plane.relaxed.y) * mix,
            plane.relaxed.z + (plane.drawn.z - plane.relaxed.z) * mix
        )
        return ReplayGripGeometry.normalize(direction)
    }

    /// Signed elbow displacement from the vertical working plane containing
    /// the shoulder→wrist chord.  Positive is outboard (away from the boat
    /// centreline), negative crosses inboard over the chord.
    public static func elbowOutboard(
        shoulder: SIMD3<Double>,
        wrist: SIMD3<Double>,
        elbow: SIMD3<Double>,
        side: Double
    ) -> Double {
        var chord = wrist - shoulder
        chord.y = 0
        if ReplayGripGeometry.lengthSquared(chord) < 1e-10 { chord = SIMD3(0, 0, 1) }
        chord = ReplayGripGeometry.normalize(chord)
        // Horizontal normal of the vertical plane through the chord.
        var outNormal = SIMD3(-chord.z, 0.0, chord.x)
        let sideSign = ReplayGripGeometry.mirrorSign(side)
        if abs(outNormal.x) > 1e-3 {
            if outNormal.x * sideSign < 0 { outNormal = -outNormal }
        } else {
            let chordSign = chord.x == 0 ? 1.0 : ReplayGripGeometry.mirrorSign(chord.x)
            if outNormal.z * sideSign * chordSign < 0 {
                // Chord nearly fore-aft-free: fall back to a stable sign.
                outNormal = -outNormal
            }
        }
        let delta = elbow - shoulder
        return delta.x * outNormal.x + delta.y * outNormal.y + delta.z * outNormal.z
    }

    /// Solution of one equipment-locked sculling arm solve.
    public struct ArmSolution: Sendable {
        public let elbow: SIMD3<Double>
        public let hand: SIMD3<Double>
        public let plane: SIMD3<Double>
        public let authority: Double
    }

    /// Solve one equipment-locked sculling arm on the flexion-scheduled elbow
    /// contract.  The wrist lands exactly on the rigid grip and both bone
    /// lengths remain authoritative; the one free degree of freedom — the
    /// elbow's station on the circle around the shoulder→wrist chord — is
    /// steered by the plane schedule, then bounded by the corridor as a
    /// safety clamp, with an up-clamp preventing an above-horizontal wing.
    public static func solveArm(
        shoulder: SIMD3<Double>,
        hand: SIMD3<Double>,
        upperArmLength: Double,
        forearmLength: Double,
        side: Double
    ) -> ArmSolution {
        let reach = ReplayGripGeometry.dot(hand - shoulder, hand - shoulder).squareRoot()
        let flexion = elbowFlexion(
            chordLength: reach,
            upperArmLength: upperArmLength,
            forearmLength: forearmLength
        )
        let authority = elbowPlaneAuthority(flexion)
        var plane = elbowPlaneDirection(side: side, authority: authority)
        let solved = ReplayTwoBoneSolver.solve3D(
            root: shoulder,
            target: hand,
            firstLength: upperArmLength,
            secondLength: forearmLength,
            bendHint: plane
        )
        var elbow = solved.joint
        let solvedHand = solved.end

        // Decompose the elbow circle into an outboard basis vector and an
        // in-working-plane down vector, then clamp the outboard coefficient
        // in closed form.
        var chord = solvedHand - shoulder
        let chordLength = ReplayGripGeometry.dot(chord, chord).squareRoot()
        if chordLength <= 1e-6 {
            return ArmSolution(elbow: elbow, hand: solvedHand, plane: plane, authority: authority)
        }
        chord /= chordLength
        let along = (upperArmLength * upperArmLength
            - forearmLength * forearmLength
            + chordLength * chordLength)
            / (2 * chordLength)
        let radius = max(0, upperArmLength * upperArmLength - along * along).squareRoot()
        if radius <= 1e-4 {
            return ArmSolution(elbow: elbow, hand: solvedHand, plane: plane, authority: authority)
        }

        // Outboard normal of the vertical working plane; perpendicular to
        // the full 3D chord because it is horizontal and the horizontal
        // chord part lies inside the plane.
        var outNormal = SIMD3(-chord.z, 0.0, chord.x)
        if ReplayGripGeometry.lengthSquared(outNormal) < 1e-10 {
            outNormal = SIMD3(ReplayGripGeometry.mirrorSign(side), 0, 0)
        }
        outNormal = ReplayGripGeometry.normalize(outNormal)
        if outNormal.x * ReplayGripGeometry.mirrorSign(side) < 0 { outNormal = -outNormal }
        var inPlaneDown = ReplayGripGeometry.normalize(
            ReplayGripGeometry.cross(chord, outNormal)
        )
        if inPlaneDown.y > 0 { inPlaneDown = -inPlaneDown }

        var station = elbow - shoulder - chord * along
        station /= radius
        var downWeight = ReplayGripGeometry.dot(station, inPlaneDown)
        var outWeight = ReplayGripGeometry.dot(station, outNormal)

        // Blend the natural station toward the chord-frame drawn station as
        // the plane gains authority; renormalising after the lerp keeps the
        // joint on the circle rather than shrinking the bend radius.
        let planeConstants = elbowPlane
        downWeight += (planeConstants.drawnDownWeight - downWeight) * authority
        outWeight += (planeConstants.drawnOutboardWeight - outWeight) * authority
        let stationNorm = (downWeight * downWeight + outWeight * outWeight).squareRoot()
        if stationNorm > 1e-6 {
            downWeight /= stationNorm
            outWeight /= stationNorm
        } else {
            downWeight = 1
            outWeight = 0
        }

        let corridor = elbowCorridor
        let maxOut = min(1, corridor.maxOutboard / radius)
        let maxIn = min(1, corridor.maxInboard / radius)
        let clampedOut = min(max(outWeight, -maxIn), maxOut)
        if clampedOut != outWeight {
            outWeight = clampedOut
            // Re-normalise on the circle without changing the vertical
            // hemisphere the plane chose — the corridor is a lateral safety
            // limit, not a pose.
            let downSign = downWeight == 0 ? 1.0 : ReplayGripGeometry.mirrorSign(downWeight)
            downWeight = downSign * max(0, 1 - outWeight * outWeight).squareRoot()
        }
        // Up-clamp: at visible flexion the joint may not rise above the
        // horizontal through the chord (the start of a wing), but nothing
        // folds it *down*.
        let minimumDown = -(1 - authority)
        if downWeight < minimumDown {
            downWeight = minimumDown
            let outSign = outWeight == 0 ? 1.0 : ReplayGripGeometry.mirrorSign(outWeight)
            outWeight = outSign
                * min(max(0, 1 - downWeight * downWeight).squareRoot(), maxOut)
        }

        plane = inPlaneDown * downWeight + outNormal * outWeight
        if ReplayGripGeometry.lengthSquared(plane) > 1e-10 {
            plane = ReplayGripGeometry.normalize(plane)
        } else {
            plane = inPlaneDown
        }
        elbow = shoulder + chord * along + plane * radius
        return ArmSolution(elbow: elbow, hand: solvedHand, plane: plane, authority: authority)
    }
}
