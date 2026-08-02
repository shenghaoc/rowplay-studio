import Foundation

/// Shared bike fit contract ported from RowPlay `bikeRig.js` and
/// `bikeSaddle.js`.  Local +Z is travel; +Y is up; lateral contacts use X.
/// All values are metres, in the same metric space as the V4 athlete.
///
/// Authored the way a bike is actually fitted: the frame comes from real road
/// geometry (≈56 cm frame, 700×25c), and the rider's hip is then *derived*
/// from their own leg length against the bottom bracket.
///
/// Contact rules (no mesh penetration): the mesh sit surface rests **on** the
/// saddle pad; wheel tyres rest **on** the ground plane
/// (axle Y == wheelRadius + tyreTube).
public enum ReplayBikeGripContract {
    // MARK: - Rider, measured from V4 bone definitions.

    /// Femur length: v4LeftLowerLeg offset from v4LeftUpperLeg.
    public static let athleteThigh = 0.4915
    /// Tibia length: v4LeftFoot offset from v4LeftLowerLeg.
    public static let athleteShin = 0.4794
    /// Ankle-to-sole drop, from the sealed foot contact offset.
    public static let athleteSoleDrop = 0.055
    /// `v4Hips` is the pelvis root, not the hip joint: the femur starts at
    /// `v4LeftUpperLeg`, 25 mm below it.
    public static let hipRootToFemoralHead = 0.025
    /// Knee flexion at bottom dead centre — the Holmes road-fit window is
    /// 25–35° and 30° is the middle of it.  Only femur + tibia count: the
    /// contact solver drives the ankle straight onto the pedal spindle.
    public static let kneeFlexionAtBDC = 30.0 * .pi / 180
    /// Femoral-head-to-pedal distance at BDC, by the law of cosines.
    public static let legReach: Double = {
        let thigh = athleteThigh
        let shin = athleteShin
        return (thigh * thigh + shin * shin
            - 2 * thigh * shin * cos(.pi - kneeFlexionAtBDC)).squareRoot()
    }()

    // MARK: - Frame, from real road geometry.

    public static let wheelRadius = 0.31
    public static let tyreTube = 0.025
    /// Outer tyre radius; also the axle height, so the tread rests on y == 0.
    public static let axleY = wheelRadius + tyreTube
    /// The bottom bracket hangs below the axle line on every road bike.
    public static let bbDrop = 0.07
    public static let bbY = axleY - bbDrop
    public static let bbZ = -0.05
    /// Crank arm length for a rider this size.
    public static let crankRadius = 0.1725
    /// Femoral-head setback behind the bottom bracket.
    public static let pelvisSetback = 0.12
    public static let pelvisZ = bbZ - pelvisSetback

    /// Head tube angle, from horizontal.  A steerer leans *back* as it rises,
    /// so the head tube top is rearward of its bottom.
    public static let headAngle = 73.0 * .pi / 180
    public static let headTubeLength = 0.155
    /// Frame stack and reach, measured from the bottom bracket.
    public static let stack = 0.575
    public static let reach = 0.385
    public static let headTopY = bbY + stack
    public static let headTopZ = bbZ + reach
    public static let headBottomY = headTopY - headTubeLength
    public static let headBottomZ = headTopZ + headTubeLength / tan(headAngle)

    /// Fork offset ahead of the steering axis.
    public static let forkRake = 0.05
    public static let frontAxleZ = headTopZ + (headTopY - axleY) / tan(headAngle) + forkRake
    public static let chainstay = 0.41
    public static let rearAxleZ = bbZ - chainstay

    // MARK: - Seating, derived from the rider against the frame.

    /// Ischial (sit-bone) surface relative to `v4Hips`, measured on the
    /// shipped GLB across the whole crank cycle: skin at |x| ∈ [0.050,
    /// 0.075] over z ∈ [−0.135, −0.095] behind the pelvis root.
    public static let sitSurfaceFromHipY = -0.158
    /// Perineal soft tissue on the centreline, same measurement.  It hangs
    /// below the ischia, which is why the saddle carries a through cut-out.
    public static let perineumFromHipY = -0.1952
    /// Soft cushion nestle.  Positive sinks the sit surface into the pad.
    public static let sitNestle = 0.005
    public static let saddlePadHalfHeight = 0.022
    /// Sit-bone contact behind the pelvis root, from the same measurement.
    public static let sitContactZFromHip = -0.115

    public static let bdcPedalY = bbY - crankRadius
    public static let femoralHeadRise: Double =
        (legReach * legReach - pelvisSetback * pelvisSetback).squareRoot()
    public static let riderHipY = bdcPedalY + femoralHeadRise + hipRootToFemoralHead
    /// Pad top follows the hip, so the sit surface always lands on the
    /// cushion.
    public static let saddlePadTopY = riderHipY + sitNestle + sitSurfaceFromHipY
    public static let saddleY = saddlePadTopY - saddlePadHalfHeight
    /// Saddle origin sits under the sit bones, not under the pelvis root.
    public static let saddleZ = pelvisZ + sitContactZFromHip
    /// Rail clamp, near the saddle's mid-length and ahead of the sit bones.
    public static let saddleClampZ = 0.05
    public static let saddleClampY = saddleY - saddlePadHalfHeight

    /// Seat tube angle, and the exposed seatpost between the frame's seat
    /// cluster and the rail clamp.
    public static let seatTubeAngle = 73.0 * .pi / 180
    public static let seatpostExposed = 0.06
    public static let seatClusterY = saddleClampY - seatpostExposed * sin(seatTubeAngle)
    public static let seatClusterZ = saddleZ + saddleClampZ + seatpostExposed * cos(seatTubeAngle)

    // MARK: - Handlebar and hoods.

    /// Stem clamp / bar centre, ahead of and just above the head tube top.
    public static let handlebarBase = SIMD3<Double>(0, headTopY + 0.015, headTopZ + 0.09)
    /// Brake hoods — where the palms actually close.  40 cm bar.
    public static let handlebarGripY = headTopY
    public static let handlebarGripZ = headTopZ + 0.175
    public static let handlebarGripHalfSpan = 0.2
    /// Hood-body grip channel around the hand-contact anchor.  The rendered
    /// hood is 36 mm across, so its analytic contact surface is the 18 mm
    /// half-section.  `hoodRotationX` is also the visual hood mesh's X
    /// rotation, keeping contact and rendering aligned.
    public static let hoodRotationX = -0.24
    public static let hoodRadius = 0.018

    public static let crankLateral = 0.09

    /// Rider hip / pelvis target, derived from leg reach.
    public static let riderRoot = SIMD3<Double>(0, riderHipY, pelvisZ)
    /// Compact residual nestle of the procedural pelvis into the seat shell.
    public static let riderPelvisOffset = SIMD3<Double>(0, 0, -0.005)

    /// Thumb opposition closing the fist onto the hood body (fitted band
    /// 1.52–1.60 measured on the shipped rig).
    public static let hoodThumbOppose = 1.56

    /// Grip closure options for one BikeErg hand: the palm-supported hood
    /// enclosure uses the opt-in wrapped finger-stage search so four fingers
    /// reach the far side while every phalanx segment remains
    /// collision-bounded, and the opposing thumb hooks underneath.
    public static func gripClosureOptions(side: Double) -> ReplayHandGripClosureOptions {
        ReplayHandGripClosureOptions(
            side: side,
            surface: ReplayHandGripSurface(radius: hoodRadius),
            thumbOppose: hoodThumbOppose,
            wrapFingerStages: true
        )
    }

    /// Axle height so the tyre outer shell rests on the ground plane.
    public static func wheelAxleY() -> Double { axleY }

    /// Authored sit-bone pad top Y in avatar-local space.
    public static func saddleTopY() -> Double { saddleY + saddlePadHalfHeight }

    /// Knee flexion (radians away from a straight leg) with the crank at
    /// `angle`, measured 0 at top dead centre and increasing forward.  This
    /// is the fit criterion the saddle height is solved against.
    public static func kneeFlexion(atCrankAngle angle: Double) -> Double {
        let pedalY = bbY + crankRadius * cos(angle)
        let pedalZ = bbZ + crankRadius * sin(angle)
        let hipY = riderHipY - hipRootToFemoralHead
        let hipZ = pelvisZ
        let reach = ((hipY - pedalY) * (hipY - pedalY)
            + (hipZ - pedalZ) * (hipZ - pedalZ)).squareRoot()
        let cosKnee = (athleteThigh * athleteThigh
            + athleteShin * athleteShin
            - reach * reach)
            / (2 * athleteThigh * athleteShin)
        return .pi - acos(min(max(cosKnee, -1), 1))
    }

    /// Hip Y that places the sit surface on the pad top (minus soft nestle).
    /// The single seating derivation, so height tweaks cannot drift the rider
    /// through the cushion.
    public static func derivedRiderHipY() -> Double {
        saddleTopY() - sitNestle - sitSurfaceFromHipY
    }
}

/// Analytic winged/cut-out saddle shape contract ported from RowPlay
/// `bikeSaddle.js`.  Local frame: origin at the saddle centre, +Z forward
/// (nose-ward), +Y up.  The top surface at the widest station is the pad top.
///
/// The rider is a standing-derived mesh whose seat region is not a plane: the
/// ischia carry on a flat 40 mm plateau, the gluteal cleft rides ~12 mm
/// higher, the perineum hangs ~37 mm lower, and the thighs sweep down forward
/// of the pelvis root.  Both problems are answered the way real performance
/// saddles answer them: a wide winged rear with a **through cut-out** down
/// the centreline, and a narrow nose that drops away.
public enum ReplayBikeSaddle {
    public struct Station: Equatable, Sendable {
        public let z: Double
        /// Shell half-width.
        public let halfWidth: Double
        /// Top surface below the pad top at the widest point.
        public let dropOuter: Double
        /// Top surface below the pad top at the channel edge.
        public let dropChannel: Double
        /// Half-width of the through cut-out; 0 where the shell is solid.
        public let cutout: Double

        public init(
            z: Double,
            halfWidth: Double,
            dropOuter: Double,
            dropChannel: Double,
            cutout: Double
        ) {
            self.z = z
            self.halfWidth = halfWidth
            self.dropOuter = dropOuter
            self.dropChannel = dropChannel
            self.cutout = cutout
        }
    }

    /// Stations along the saddle's own Z, nose-ward positive.  Every value is
    /// the measured skin envelope minus clearance, not styling.
    public static let stations: [Station] = [
        Station(z: -0.05, halfWidth: 0.03, dropOuter: 0.012, dropChannel: 0.012, cutout: 0),
        Station(z: -0.03, halfWidth: 0.06, dropOuter: 0.002, dropChannel: 0.004, cutout: 0),
        Station(z: -0.015, halfWidth: 0.073, dropOuter: 0.0, dropChannel: 0.004, cutout: 0.018),
        Station(z: 0.0, halfWidth: 0.075, dropOuter: 0.0, dropChannel: 0.007, cutout: 0.024),
        Station(z: 0.015, halfWidth: 0.068, dropOuter: 0.001, dropChannel: 0.014, cutout: 0.024),
        Station(z: 0.028, halfWidth: 0.056, dropOuter: 0.002, dropChannel: 0.021, cutout: 0.024),
        Station(z: 0.045, halfWidth: 0.046, dropOuter: 0.018, dropChannel: 0.021, cutout: 0.024),
        Station(z: 0.06, halfWidth: 0.038, dropOuter: 0.02, dropChannel: 0.022, cutout: 0.024),
        Station(z: 0.08, halfWidth: 0.032, dropOuter: 0.024, dropChannel: 0.026, cutout: 0.024),
        Station(z: 0.1, halfWidth: 0.027, dropOuter: 0.028, dropChannel: 0.029, cutout: 0.022),
        Station(z: 0.115, halfWidth: 0.024, dropOuter: 0.04, dropChannel: 0.041, cutout: 0.014),
        Station(z: 0.13, halfWidth: 0.022, dropOuter: 0.046, dropChannel: 0.046, cutout: 0),
        Station(z: 0.15, halfWidth: 0.02, dropOuter: 0.053, dropChannel: 0.053, cutout: 0),
        Station(z: 0.17, halfWidth: 0.017, dropOuter: 0.062, dropChannel: 0.062, cutout: 0),
    ]

    /// How sharply the shell climbs from the channel to the wing.  A low
    /// exponent gives pronounced wings, which is what holds the ischia up
    /// while the cleft between them clears.
    public static let channelFalloff = 0.22

    /// Shell thickness below the top surface.
    public static let shellThickness = 0.016

    public static let rearZ = stations[0].z
    public static let noseZ = stations[stations.count - 1].z
    public static let length = noseZ - rearZ
    public static let maxHalfWidth = stations.map(\.halfWidth).max() ?? 0

    /// Station values interpolated at an arbitrary local Z, or `nil` beyond
    /// the saddle's own ends.
    public static func station(at z: Double) -> Station? {
        guard let first = stations.first, let last = stations.last,
              z >= first.z, z <= last.z else { return nil }
        for index in 1..<stations.count {
            let upper = stations[index]
            if z > upper.z { continue }
            let lower = stations[index - 1]
            let span = upper.z - lower.z
            let t = span <= 0 ? 0 : (z - lower.z) / span
            return Station(
                z: z,
                halfWidth: lower.halfWidth + (upper.halfWidth - lower.halfWidth) * t,
                dropOuter: lower.dropOuter + (upper.dropOuter - lower.dropOuter) * t,
                dropChannel: lower.dropChannel + (upper.dropChannel - lower.dropChannel) * t,
                cutout: lower.cutout + (upper.cutout - lower.cutout) * t
            )
        }
        return nil
    }

    /// Top surface of the saddle at a local (x, z), as a drop below the pad
    /// top — or `nil` where there is no material: outside the shell, or
    /// inside the cut-out.  The single definition of "is the saddle here";
    /// the penetration guard and the mesh builder both read it.
    public static func drop(atX x: Double, z: Double) -> Double? {
        guard let station = station(at: z) else { return nil }
        let ax = abs(x)
        if ax > station.halfWidth { return nil }
        if ax < station.cutout { return nil }
        let inner = max(station.cutout, 0)
        let span = station.halfWidth - inner
        let t = span <= 1e-6 ? 1 : min(max((ax - inner) / span, 0), 1)
        return station.dropOuter
            + (station.dropChannel - station.dropOuter) * pow(1 - t, channelFalloff)
    }
}
