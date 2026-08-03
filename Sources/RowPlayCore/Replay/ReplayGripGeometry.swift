import Foundation

/// Geometry-constrained hand-grip channel model shared by all three sports.
///
/// Port of the hand-measurement half of RowPlay `handGrip.ts`.  A grip is not
/// "a palm near a target plus curled finger constants": the equipment must lie
/// inside a collision-checked digit enclosure.  This file owns where a
/// cylinder of radius R sits in the hand — derived from the pinned SkiErg fist
/// measurements — and the grip-frame orientation math that aligns the hand's
/// authored curl axis to an equipment axis.
public enum ReplayGripGeometry {
    /// Authored finger-curl axis of the hand, hand-local, for the **right**
    /// hand; `y` and `z` mirror for the left.  Every phalanx helper flexes
    /// about its own local +X, and this is that axis expressed in the hand's
    /// frame.  Measured on the SkiErg pole grip with the palm cup applied.
    public static let handCurlAxisRight = SIMD3<Double>(-0.61, 0.16, 0.77)

    /// Centre of the closed fist's grip channel, hand-local, right hand;
    /// `x` mirrors for the left.  This is the centre of the circle the curled
    /// middle finger actually traces.  Fitted with the palm cup applied.
    public static let handFistCentre = SIMD3<Double>(0.0393, -0.0088, 0.0142)

    /// Radius of the circle the closed fist's finger joints trace — the
    /// channel the reference grip was fitted in.
    public static let handFistRadius = 0.0169

    /// Radius of the equipment the fist channel above was fitted around — the
    /// SkiErg pole rubber.  Paired with `handFistRadius` it is the rig's
    /// digit-flesh calibration.
    public static let handFistReferenceGripRadius = 0.016

    /// Authored palm-surface contact of the right hand — the sealed V4
    /// `v4RightHand` contact offset, repeated here so Core stays free of the
    /// runtime contract parse; `ReplayAthleteReferenceManifest` validates the
    /// loaded contract against this value.
    public static let handPalmContact = SIMD3<Double>(0.08, -0.01, 0.035)

    /// Inward palm normal of the right hand: from the authored palm-surface
    /// contact toward the fitted fist-channel centre.  Left mirrors x.
    public static let handPalmNormalIn: SIMD3<Double> = {
        let direction = handFistCentre - handPalmContact
        let length = (direction.x * direction.x + direction.y * direction.y
            + direction.z * direction.z).squareRoot()
        return direction / length
    }()

    /// Distance from the palm skin to the surface of a held cylinder — the
    /// seat flesh the fist measurement already encodes.
    public static let handGripSeatFlesh: Double = {
        let delta = handFistCentre - handPalmContact
        let distance = (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
        return distance - handFistRadius
    }()

    /// Hand long axis — wrist origin toward the middle-finger root — measured
    /// from the sealed V4 helper rest transforms (right hand; x mirrors).
    public static let handLongAxisRight = SIMD3<Double>(0.926, 0.105, 0.363)

    /// Outward palm normal measured from the shipped V4 bind geometry (right
    /// hand; x mirrors).  Distinct from `handPalmNormalIn`, the construction
    /// ray used to seat a cylinder inside the hand.
    public static let handPalmNormalOutRight = SIMD3<Double>(-0.1052, -0.8513, 0.514)

    /// Palm-cup carrying posture the grip channel was fitted under: rotation
    /// about the `v4*Fingers` helper's local Y applied before curling.
    public static let handClosureCup = 0.14

    /// Hand-local centre of the channel that a cylinder of `radius` occupies
    /// when held.  `handChannelCentre(handFistRadius)` reproduces the pinned
    /// SkiErg fist centre exactly; larger radii seat proportionally further
    /// from the palm.  x mirrors by side.
    public static func handChannelCentre(
        radius: Double,
        side: ReplayHandSide
    ) -> SIMD3<Double> {
        let seat = handGripSeatFlesh + radius
        var centre = handPalmContact + handPalmNormalIn * seat
        centre.x *= mirrorSign(side)
        return centre
    }

    /// Hand-local curl axis, mirrored the way the shipped rig mirrors hands.
    public static func handCurlAxis(side: ReplayHandSide) -> SIMD3<Double> {
        let mirror = mirrorSign(side)
        return normalize(
            SIMD3(
                handCurlAxisRight.x,
                mirror * handCurlAxisRight.y,
                mirror * handCurlAxisRight.z
            )
        )
    }

    /// Curl axis signed from the pinky side toward the index/thumb side.
    /// Grip frames must use this signed form or the left thumb lands on the
    /// wrong end of a stopped handle.
    public static func handCurlAxisThumbward(side: ReplayHandSide) -> SIMD3<Double> {
        handCurlAxis(side: side) * mirrorSign(side)
    }

    public static func handLongAxis(side: ReplayHandSide) -> SIMD3<Double> {
        let mirror = mirrorSign(side)
        return normalize(
            SIMD3(mirror * handLongAxisRight.x, handLongAxisRight.y, handLongAxisRight.z)
        )
    }

    public static func handPalmNormalOut(side: ReplayHandSide) -> SIMD3<Double> {
        let mirror = mirrorSign(side)
        return normalize(
            SIMD3(
                mirror * handPalmNormalOutRight.x,
                handPalmNormalOutRight.y,
                handPalmNormalOutRight.z
            )
        )
    }

    /// Orient a hand so its authored grip channel encloses the equipment: the
    /// curl axis lands exactly on the thumb-ward signed shaft direction and
    /// the remaining spin about the shaft is resolved so the channel sits on
    /// the requested side of the wrist.  Returns the hand quaternion in the
    /// hand's parent frame.  Equipment roll about its own axis cancels out —
    /// "the handle rolls within the fingers".
    ///
    /// - Parameters:
    ///   - shaftDirThumbward: equipment channel axis in the hand's parent
    ///     frame, already signed from the pinky side toward the thumb side.
    ///   - rollReference: desired direction of (channel centre − wrist) in
    ///     the same frame — which side of the shaft the palm rides on.
    ///   - rollVectorLocal: hand-local vector aligned to `rollReference` when
    ///     resolving the remaining spin; defaults to the channel-centre
    ///     construction ray.
    public static func orientHandToGripChannel(
        side: ReplayHandSide,
        radius: Double,
        shaftDirThumbward: SIMD3<Double>,
        rollReference: SIMD3<Double>,
        baseQuaternion: ReplayQuaternion,
        rollVectorLocal: SIMD3<Double>? = nil
    ) -> ReplayQuaternion {
        var hand = baseQuaternion
        let worldCurl = hand.act(handCurlAxisThumbward(side: side))
        let target = normalize(shaftDirThumbward)
        hand = ReplayQuaternion(from: worldCurl, to: target) * hand

        var rollLocal: SIMD3<Double>
        if let rollVectorLocal {
            rollLocal = normalize(rollVectorLocal)
        } else {
            rollLocal = normalize(handChannelCentre(radius: radius, side: side))
        }
        var axis = hand.act(rollLocal)
        var roll = normalize(rollReference)
        axis -= target * dot(axis, target)
        roll -= target * dot(roll, target)
        if lengthSquared(axis) > 1e-8, lengthSquared(roll) > 1e-8 {
            axis = normalize(axis)
            roll = normalize(roll)
            let cosine = min(max(dot(axis, roll), -1), 1)
            // Both vectors are perpendicular to the shaft, so their signed
            // angle is an axial roll.  atan2 keeps the exact 180° case on the
            // shaft axis.
            let sine = dot(cross(axis, roll), target)
            hand = ReplayQuaternion(axis: target, angle: atan2(sine, cosine)) * hand
        }
        return hand
    }

    /// Spend the grip frame's free spin about the shaft on wrist flatness,
    /// bounded so the sport-requested palm side remains authoritative.
    public static func refineGripSpinForWrist(
        hand: ReplayQuaternion,
        side: ReplayHandSide,
        shaftDir: SIMD3<Double>,
        forearmDir: SIMD3<Double>,
        maxPalmDeviation: Double
    ) -> ReplayQuaternion {
        let shaft = normalize(shaftDir)
        var long = hand.act(handLongAxis(side: side))
        long -= shaft * dot(long, shaft)
        var forearm = forearmDir - shaft * dot(forearmDir, shaft)
        guard lengthSquared(long) >= 1e-8, lengthSquared(forearm) >= 1e-6 else { return hand }
        long = normalize(long)
        forearm = normalize(forearm)
        let angle = atan2(dot(cross(long, forearm), shaft), dot(long, forearm))
        let clamped = min(max(angle, -maxPalmDeviation), maxPalmDeviation)
        guard abs(clamped) >= 1e-6 else { return hand }
        return ReplayQuaternion(axis: shaft, angle: clamped) * hand
    }

    /// Let a held shaft run diagonally across the palm to relieve remaining
    /// wrist bend.  Rotation is about the true palm normal, so palm facing is
    /// preserved.
    public static func refineGripTiltForWrist(
        hand: ReplayQuaternion,
        side: ReplayHandSide,
        forearmDir: SIMD3<Double>,
        comfort: Double,
        maxTilt: Double,
        strength: Double = 1
    ) -> ReplayQuaternion {
        let palm = normalize(hand.act(handPalmNormalOut(side: side)))
        var long = hand.act(handLongAxis(side: side))
        long -= palm * dot(long, palm)
        var forearm = forearmDir - palm * dot(forearmDir, palm)
        guard lengthSquared(long) >= 1e-8, lengthSquared(forearm) >= 1e-6 else { return hand }
        long = normalize(long)
        forearm = normalize(forearm)
        let angle = atan2(dot(cross(long, forearm), palm), dot(long, forearm))
        let excess = max(0, abs(angle) - comfort)
        let clampedStrength = min(max(strength, 0), 1)
        let clamped = (angle < 0 ? -1.0 : 1.0) * min(excess, maxTilt) * clampedStrength
        guard abs(clamped) >= 1e-6 else { return hand }
        return ReplayQuaternion(axis: palm, angle: clamped) * hand
    }

    static func mirrorSign(_ side: ReplayHandSide) -> Double {
        side.rawValue
    }

    static func mirrorSign(_ value: Double) -> Double {
        value < 0 ? -1 : 1
    }

    static func normalize(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let lengthSquared = lengthSquared(vector)
        guard lengthSquared > 1e-24 else { return SIMD3(0, 1, 0) }
        return vector / lengthSquared.squareRoot()
    }

    static func lengthSquared(_ vector: SIMD3<Double>) -> Double {
        vector.x * vector.x + vector.y * vector.y + vector.z * vector.z
    }

    static func dot(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        first.x * second.x + first.y * second.y + first.z * second.z
    }

    static func cross(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            first.y * second.z - first.z * second.y,
            first.z * second.x - first.x * second.z,
            first.x * second.y - first.y * second.x
        )
    }
}
