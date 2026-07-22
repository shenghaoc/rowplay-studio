import Foundation
import RealityKit
import simd

/// Equipment-contact targets for a V4 athlete instance.
struct ReplayAthleteContactTargets {
    var pelvis: SIMD3<Float>
    var leftHand: SIMD3<Float>
    var rightHand: SIMD3<Float>
    var leftFoot: SIMD3<Float>
    var rightFoot: SIMD3<Float>
}

/// Measured residual after a contact pass.
struct ReplayAthleteContactError: Equatable, Sendable {
    var leftHand: Float
    var rightHand: Float
    var leftFoot: Float
    var rightFoot: Float
    var pelvis: Float

    var maximumPalmError: Float { max(leftHand, rightHand) }
    var maximumSoleError: Float { max(leftFoot, rightFoot) }
}

/// Aligns a prepared V4 pose onto native equipment contacts.
///
/// Phase 11 prioritises logical motion and stable contact over mesh perfection.
/// Minor interpenetration (`穿模`) is accepted and deferred to Phase 12.
@MainActor
enum ReplayAthleteContactSolver {
    /// Soft residual budget used by tests. Not a photoreal contact claim.
    static let softContactBudgetMeters: Float = 0.12

    /// Place the athlete root so its pelvis sits on the equipment support, then
    /// snap palm/sole contact markers to equipment targets.
    static func constrain(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplayAthleteContactError {
        // Pelvis follows seat/saddle/standing hip support.
        instance.root.setPosition(targets.pelvis, relativeTo: space)

        if let leftHand = instance.leftHandContact {
            leftHand.setPosition(targets.leftHand, relativeTo: space)
        }
        if let rightHand = instance.rightHandContact {
            rightHand.setPosition(targets.rightHand, relativeTo: space)
        }
        if let leftFoot = instance.leftFootContact {
            leftFoot.setPosition(targets.leftFoot, relativeTo: space)
        }
        if let rightFoot = instance.rightFootContact {
            rightFoot.setPosition(targets.rightFoot, relativeTo: space)
        }

        return measure(instance: instance, targets: targets, relativeTo: space)
    }

    static func measure(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplayAthleteContactError {
        func distance(_ entity: Entity?, _ target: SIMD3<Float>) -> Float {
            guard let entity else { return .infinity }
            let p = entity.position(relativeTo: space)
            let d = p - target
            let length = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
            return length.isFinite ? length : .infinity
        }

        let pelvisError: Float = {
            let p = instance.root.position(relativeTo: space)
            let d = p - targets.pelvis
            let length = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
            return length.isFinite ? length : .infinity
        }()

        return ReplayAthleteContactError(
            leftHand: distance(instance.leftHandContact, targets.leftHand),
            rightHand: distance(instance.rightHandContact, targets.rightHand),
            leftFoot: distance(instance.leftFootContact, targets.leftFoot),
            rightFoot: distance(instance.rightFootContact, targets.rightFoot),
            pelvis: pelvisError
        )
    }
}
