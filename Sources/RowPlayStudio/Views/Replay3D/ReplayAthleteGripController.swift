import Foundation
import RealityKit
import RowPlayCore
import simd

/// Install-time digit-closure state for one athlete instance.
///
/// The geometric closure solve runs once per (sport, hand) against the
/// contract's authored helper rest transforms — never per frame.  Per frame,
/// only the cached flex/oppose angles are composed onto each helper's rest
/// rotation, strictly after base-pose sampling and contact correction, which
/// mirrors the web controller's `applyGripHelpers` ordering.
@MainActor
final class ReplayAthleteGripController {
    /// Closure reports per hand for tests and diagnostics.
    let leftClosure: ReplayHandGripClosure
    let rightClosure: ReplayHandGripClosure

    /// Cached solved rotation per helper joint name, including the palm-cup
    /// roll on the `v4*Fingers` nodes.
    private let rotationByHelper: [String: simd_quatf]

    init?(contract: ReplayAthleteContract, sport: Sport) {
        let options = Self.closureOptions(for: sport)

        func chains(side: ReplayHandSide) -> [ReplayHandDigitChain] {
            let handBone = side == .left ? "v4LeftHand" : "v4RightHand"
            return ReplayHandDigitChain.collect(
                side: side,
                handBoneName: handBone,
                restLocalTransform: { name in
                    guard let rest = contract.restLocalTransform(of: name) else { return nil }
                    return (rest.translation, rest.rotation)
                },
                parentName: { contract.parentName(of: $0) }
            )
        }

        let leftChains = chains(side: .left)
        let rightChains = chains(side: .right)
        guard leftChains.count == 5, rightChains.count == 5 else {
            return nil
        }

        guard let left = ReplayHandClosure.solve(
            chains: leftChains,
            options: options(.left)
        ), let right = ReplayHandClosure.solve(
            chains: rightChains,
            options: options(.right)
        ), left.poses.count == 15,
           right.poses.count == 15,
           left.contacts.count == 5,
           right.contacts.count == 5 else {
            return nil
        }
        self.leftClosure = left
        self.rightClosure = right

        var rotations: [String: simd_quatf] = [:]
        func store(closure: ReplayHandGripClosure, side: ReplayHandSide) {
            for pose in closure.poses {
                guard let rest = contract.restLocalTransform(of: pose.helper) else { continue }
                var rotation = rest.rotation
                if pose.oppose != 0 {
                    rotation = rotation
                        * ReplayQuaternion(axis: SIMD3(0, 0, 1), angle: pose.oppose)
                }
                rotation = rotation
                    * ReplayQuaternion(axis: SIMD3(1, 0, 0), angle: -pose.flex)
                rotations[pose.helper] = Self.floatQuaternion(rotation)
            }
            // Palm-cup carrying posture on the `v4*Fingers` node — the pose
            // the grip channel was fitted under.
            let cupName = side == .left ? "v4LeftFingers" : "v4RightFingers"
            if let rest = contract.restLocalTransform(of: cupName) {
                let cup = rest.rotation * ReplayQuaternion(
                    axis: SIMD3(0, 1, 0),
                    angle: -side.rawValue * ReplayGripGeometry.handClosureCup
                )
                rotations[cupName] = Self.floatQuaternion(cup)
            }
        }
        store(closure: left, side: .left)
        store(closure: right, side: .right)
        self.rotationByHelper = rotations
    }

    /// Solved local rotation for a helper joint, or `nil` when the helper is
    /// not part of the grip closure.
    func solvedRotation(forHelper name: String) -> simd_quatf? {
        rotationByHelper[name]
    }

    func closure(forSide side: ReplayHandSide) -> ReplayHandGripClosure {
        side == .left ? leftClosure : rightClosure
    }

    static func closureOptions(
        for sport: Sport
    ) -> (ReplayHandSide) -> ReplayHandGripClosureOptions {
        switch sport {
        case .rower:
            { ReplayRowGripContract.gripClosureOptions(side: $0) }
        case .skierg:
            { ReplaySkiGripContract.gripClosureOptions(side: $0) }
        case .bike:
            { ReplayBikeGripContract.gripClosureOptions(side: $0) }
        }
    }

    /// Grip-channel effector offset override for the contact solver: the
    /// authored palm-surface contact replaced with the sport's actual channel
    /// centre — SkiErg closes a full fist, RowErg and BikeErg seat larger
    /// radii proportionally further from the palm.
    static func effectorOffset(
        for sport: Sport,
        side: ReplayHandSide
    ) -> SIMD3<Double> {
        switch sport {
        case .skierg:
            var centre = ReplayGripGeometry.handFistCentre
            centre.x *= side.rawValue
            return centre
        case .rower:
            return ReplayGripGeometry.handChannelCentre(
                radius: ReplayRowGripContract.scullGrip.radius,
                side: side
            )
        case .bike:
            return ReplayGripGeometry.handChannelCentre(
                radius: ReplayBikeGripContract.hoodRadius,
                side: side
            )
        }
    }

    private static func floatQuaternion(_ quaternion: ReplayQuaternion) -> simd_quatf {
        simd_quatf(
            ix: Float(quaternion.x),
            iy: Float(quaternion.y),
            iz: Float(quaternion.z),
            r: Float(quaternion.w)
        ).normalized
    }
}
