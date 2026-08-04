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
    private let leftTerminalHandBone: String
    private let rightTerminalHandBone: String
    private let leftCupHelper: String
    private let rightCupHelper: String

    /// Cached solved rotation per helper joint name, including the structurally
    /// resolved palm-cup helper roll.
    private let rotationByHelper: [String: simd_quatf]

    init?(contract: ReplayAthleteContract, sport: Sport) {
        let options = Self.closureOptions(for: sport)

        func terminalHandBone(side: ReplayHandSide) -> String? {
            let role: ReplayAthleteContactRole = side == .left ? .leftHand : .rightHand
            return contract.contacts.first(where: { $0.role == role })?.bone
        }
        guard let leftHandBone = terminalHandBone(side: .left),
              let rightHandBone = terminalHandBone(side: .right) else {
            return nil
        }
        func chains(side: ReplayHandSide, handBone: String) -> [ReplayHandDigitChain] {
            ReplayHandDigitChain.collect(
                side: side,
                handBoneName: handBone,
                restLocalTransform: { name in
                    guard let rest = contract.restLocalTransform(of: name) else { return nil }
                    return (rest.translation, rest.rotation)
                },
                parentName: { contract.parentName(of: $0) }
            )
        }

        let leftChains = chains(side: .left, handBone: leftHandBone)
        let rightChains = chains(side: .right, handBone: rightHandBone)
        guard leftChains.count == 5,
              rightChains.count == 5,
              let leftCupHelper = Self.cupHelperName(
                  in: leftChains,
                  terminalHandBone: leftHandBone,
                  contract: contract
              ),
              let rightCupHelper = Self.cupHelperName(
                  in: rightChains,
                  terminalHandBone: rightHandBone,
                  contract: contract
              ) else {
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

        var rotations: [String: simd_quatf] = [:]
        func store(
            closure: ReplayHandGripClosure,
            side: ReplayHandSide,
            cupHelper: String
        ) -> Bool {
            for pose in closure.poses {
                guard let rest = contract.restLocalTransform(of: pose.helper) else { return false }
                var rotation = rest.rotation
                if pose.oppose != 0 {
                    rotation = rotation
                        * ReplayQuaternion(axis: SIMD3(0, 0, 1), angle: pose.oppose)
                }
                rotation = rotation
                    * ReplayQuaternion(axis: SIMD3(1, 0, 0), angle: -pose.flex)
                rotations[pose.helper] = Self.floatQuaternion(rotation)
            }
            guard let rest = contract.restLocalTransform(of: cupHelper) else { return false }
            let cup = rest.rotation * ReplayQuaternion(
                axis: SIMD3(0, 1, 0),
                angle: -side.rawValue * ReplayGripGeometry.handClosureCup
            )
            rotations[cupHelper] = Self.floatQuaternion(cup)
            return true
        }
        guard store(closure: left, side: .left, cupHelper: leftCupHelper),
              store(closure: right, side: .right, cupHelper: rightCupHelper) else {
            return nil
        }
        self.leftClosure = left
        self.rightClosure = right
        self.leftTerminalHandBone = leftHandBone
        self.rightTerminalHandBone = rightHandBone
        self.leftCupHelper = leftCupHelper
        self.rightCupHelper = rightCupHelper
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

    func terminalHandBone(forSide side: ReplayHandSide) -> String {
        side == .left ? leftTerminalHandBone : rightTerminalHandBone
    }

    func cupHelper(forSide side: ReplayHandSide) -> String {
        side == .left ? leftCupHelper : rightCupHelper
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

    /// Sport-keyed hand-local channel point used directly by runtime contact
    /// solving and measurement. The contract's raw palm point is provenance,
    /// not a second runtime effector.
    static func channelOffset(
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

    /// Resolve the one common palm-cup helper traversed by all four finger
    /// chains. The thumb is parented directly to the terminal hand bone and
    /// therefore must not introduce a second cup helper.
    private static func cupHelperName(
        in chains: [ReplayHandDigitChain],
        terminalHandBone: String,
        contract: ReplayAthleteContract
    ) -> String? {
        let fingerChains = chains.filter { $0.digit != .thumb }
        let thumbChains = chains.filter { $0.digit == .thumb }
        guard fingerChains.count == 4,
              thumbChains.count == 1 else {
            return nil
        }

        func directHandChild(for helper: String) -> String? {
            var current = helper
            var visited = Set<String>()
            while visited.insert(current).inserted,
                  let parent = contract.parentName(of: current) {
                if parent == terminalHandBone {
                    return current
                }
                current = parent
            }
            return nil
        }

        let names = fingerChains.compactMap { chain in
            chain.joints.first.flatMap { directHandChild(for: $0.helper) }
        }
        guard names.count == fingerChains.count,
              Set(names).count == 1,
              let helper = contract.helpers.first(where: { $0.name == names[0] }),
              helper.parent == terminalHandBone else {
            return nil
        }
        return helper.name
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
