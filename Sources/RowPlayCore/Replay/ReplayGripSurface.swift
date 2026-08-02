import Foundation

/// The held **equipment** surface a hand closes on.
///
/// `radius` is the rendered rubber, shaft, or hood body — not the hand's
/// fitted channel radius.  The two differ by the pad flesh, and the closure
/// solver adds that flesh itself: bone points come to rest at
/// `radius + flesh`.  Passing the channel radius instead double-counts the
/// flesh, seating the axis ~0.9 mm deeper into the palm.
public struct ReplayHandGripSurface: Equatable, Sendable {
    public let radius: Double

    /// Signed axial coordinate (along the thumb-ward channel axis, from the
    /// channel centre) of a flat handle end for the thumb to press — the
    /// scull rubber's thumb stop.  `nil` for continuous shafts.
    public let thumbEndAxial: Double?

    public init(radius: Double, thumbEndAxial: Double? = nil) {
        self.radius = radius
        self.thumbEndAxial = thumbEndAxial
    }
}

/// One solved digit-stage rotation: rest × oppose × flex, as radians.
public struct ReplayHandDigitStagePose: Equatable, Sendable {
    public let helper: String
    public let flex: Double
    public let oppose: Double

    public init(helper: String, flex: Double, oppose: Double) {
        self.helper = helper
        self.flex = flex
        self.oppose = oppose
    }
}

public struct ReplayHandDigitContactReport: Equatable, Sendable {
    public let digit: ReplayHandDigit
    /// Distance of the closest bone point to the equipment surface
    /// (m, signed: negative = penetration).
    public let surfaceDistance: Double
    /// Closest complete downstream phalanx segment to the surface when a
    /// final-enclosure contract requests segment collision proof.
    public let segmentSurfaceDistance: Double?
    /// True when the digit stopped because it reached the surface, not its
    /// flex limit.
    public let contact: Bool
    /// Solved tip position in hand-local space.
    public let tip: SIMD3<Double>

    public init(
        digit: ReplayHandDigit,
        surfaceDistance: Double,
        segmentSurfaceDistance: Double?,
        contact: Bool,
        tip: SIMD3<Double>
    ) {
        self.digit = digit
        self.surfaceDistance = surfaceDistance
        self.segmentSurfaceDistance = segmentSurfaceDistance
        self.contact = contact
        self.tip = tip
    }
}

public struct ReplayHandGripClosure: Equatable, Sendable {
    public let poses: [ReplayHandDigitStagePose]
    public let contacts: [ReplayHandDigitContactReport]

    public init(poses: [ReplayHandDigitStagePose], contacts: [ReplayHandDigitContactReport]) {
        self.poses = poses
        self.contacts = contacts
    }
}

public enum ReplayHandDigit: String, CaseIterable, Sendable {
    case index
    case middle
    case ring
    case pinky
    case thumb
}

/// One digit joint's rest transform in hand-local space.
public struct ReplayHandDigitJoint: Equatable, Sendable {
    public let helper: String
    public let position: SIMD3<Double>
    public let quaternion: ReplayQuaternion

    public init(helper: String, position: SIMD3<Double>, quaternion: ReplayQuaternion) {
        self.helper = helper
        self.position = position
        self.quaternion = quaternion
    }
}

/// One hand digit's rest chain in hand-local space, proximal → distal.
public struct ReplayHandDigitChain: Equatable, Sendable {
    public let digit: ReplayHandDigit
    public let joints: [ReplayHandDigitJoint]
    /// Estimated distal-tip length beyond the last joint (m).
    public let tipLength: Double
    /// Rest transform (relative to the hand) of the `v4*Fingers` palm-cup
    /// helper the chain hangs under, when there is one.  Thumbs parent the
    /// hand directly and carry no cup node.
    public let cupNode: ReplayHandDigitJoint?

    public init(
        digit: ReplayHandDigit,
        joints: [ReplayHandDigitJoint],
        tipLength: Double,
        cupNode: ReplayHandDigitJoint?
    ) {
        self.digit = digit
        self.joints = joints
        self.tipLength = tipLength
        self.cupNode = cupNode
    }

    /// Extract one hand's digit chains from a V4 skeleton in hand-local rest
    /// space.  `restLocalTransform` returns a bone's rest transform relative
    /// to its parent; `parentName` walks the hierarchy.  Chains that cannot be
    /// completed back to the hand bone are skipped, mirroring the web loader.
    public static func collect(
        side: Double,
        handBoneName: String,
        restLocalTransform: (String) -> (translation: SIMD3<Double>, rotation: ReplayQuaternion)?,
        parentName: (String) -> String?
    ) -> [ReplayHandDigitChain] {
        let prefix = side < 0 ? "v4Left" : "v4Right"
        let digits: [(ReplayHandDigit, [String])] = [
            (.index, ["\(prefix)IndexProximal", "\(prefix)IndexIntermediate", "\(prefix)IndexDistal"]),
            (.middle, ["\(prefix)MiddleProximal", "\(prefix)MiddleIntermediate", "\(prefix)MiddleDistal"]),
            (.ring, ["\(prefix)RingProximal", "\(prefix)RingIntermediate", "\(prefix)RingDistal"]),
            (.pinky, ["\(prefix)PinkyProximal", "\(prefix)PinkyIntermediate", "\(prefix)PinkyDistal"]),
            (.thumb, ["\(prefix)Thumb", "\(prefix)ThumbIntermediate", "\(prefix)ThumbDistal"]),
        ]
        var chains: [ReplayHandDigitChain] = []
        for (digit, names) in digits {
            var joints: [ReplayHandDigitJoint] = []
            var cupNode: ReplayHandDigitJoint?
            var complete = true
            for name in names {
                // Walk ancestors from the bone up to (excluding) the hand.
                var stack: [String] = []
                var current: String? = name
                while let node = current, node != handBoneName {
                    stack.append(node)
                    current = parentName(node)
                }
                guard current == handBoneName else {
                    complete = false
                    break
                }
                var position = SIMD3<Double>(0, 0, 0)
                var quaternion = ReplayQuaternion.identity
                var resolved = true
                for node in stack.reversed() {
                    guard let local = restLocalTransform(node) else {
                        resolved = false
                        break
                    }
                    position += quaternion.act(local.translation)
                    quaternion = quaternion * local.rotation
                    if cupNode == nil, node == "\(prefix)Fingers" {
                        cupNode = ReplayHandDigitJoint(
                            helper: node,
                            position: position,
                            quaternion: quaternion
                        )
                    }
                }
                guard resolved else {
                    complete = false
                    break
                }
                joints.append(
                    ReplayHandDigitJoint(helper: name, position: position, quaternion: quaternion)
                )
            }
            guard complete, joints.count >= 3 else { continue }
            let span = joints[2].position - joints[1].position
            let spanLength = (span.x * span.x + span.y * span.y + span.z * span.z).squareRoot()
            let tipLength = max(0.012, spanLength * 0.92)
            chains.append(
                ReplayHandDigitChain(
                    digit: digit,
                    joints: joints,
                    tipLength: tipLength,
                    cupNode: cupNode
                )
            )
        }
        return chains
    }
}
