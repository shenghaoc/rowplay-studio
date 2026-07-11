import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Articulated athlete body hierarchy with named pivots.
///
/// Builds a pelvis → torso → shoulders → head chain,
/// shoulders → arms → hands chains, and
/// pelvis → thighs → shins → feet chains. Joint rotations are applied
/// around anatomical pivots.
@MainActor
final class ReplayAthleteRig {
    // MARK: - Entity References

    let pelvis = Entity()
    let torso = Entity()
    let shoulders = Entity()
    let head = Entity()

    let upperArmL = Entity()
    let forearmL = Entity()
    let handL = Entity()

    let upperArmR = Entity()
    let forearmR = Entity()
    let handR = Entity()

    let thighL = Entity()
    let shinL = Entity()
    let footL = Entity()

    let thighR = Entity()
    let shinR = Entity()
    let footR = Entity()

    // MARK: - Build

    /// Build the articulated hierarchy into the given parent entity.
    ///
    /// - Parameters:
    ///   - parent: The entity to attach the pelvis to.
    ///   - seated: Whether the athlete is seated (affects proportions).
    ///   - accent: Accent color for sport-specific elements.
    ///   - opacity: Material opacity (1.0 for live, <1 for ghost).
    func build(
        into parent: Entity,
        seated: Bool,
        accent: Color,
        opacity: Float
    ) {
        let skinMat = ReplayMeshFactory.skinMaterial(opacity: opacity)
        let kitMat = ReplayMeshFactory.kitMaterial(opacity: opacity)
        let kitDarkMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)
        let shoeMat = ReplayMeshFactory.shoeMaterial(opacity: opacity)
        let hairMat = ReplayMeshFactory.hairMaterial(opacity: opacity)

        let torsoHeight: Float = seated ? 0.35 : 0.45
        let torsoBaseY: Float = seated ? 0.48 : 0.95

        // Name all entities for debugging/tests
        pelvis.name = "pelvis"
        torso.name = "torso"
        shoulders.name = "shoulders"
        head.name = "head"
        upperArmL.name = "upperArm-L"
        forearmL.name = "forearm-L"
        handL.name = "hand-L"
        upperArmR.name = "upperArm-R"
        forearmR.name = "forearm-R"
        handR.name = "hand-R"
        thighL.name = "thigh-L"
        shinL.name = "shin-L"
        footL.name = "foot-L"
        thighR.name = "thigh-R"
        shinR.name = "shin-R"
        footR.name = "foot-R"

        // Pelvis
        parent.addChild(pelvis)

        // Torso
        let torsoMesh = MeshResource.generateBox(
            size: SIMD3(0.30, torsoHeight, 0.18)
        )
        let torsoModel = ModelEntity(mesh: torsoMesh, materials: [kitMat])
        torsoModel.position = SIMD3(0, torsoHeight / 2, 0)
        torsoModel.name = "torso-model"
        torso.addChild(torsoModel)
        pelvis.addChild(torso)

        // Shoulders (pivot point at top of torso)
        shoulders.position = SIMD3(0, torsoHeight, 0)
        torso.addChild(shoulders)

        // Head
        let headEntity = ReplayMeshFactory.headEntity(
            skinMaterial: skinMat,
            hairMaterial: hairMat
        )
        headEntity.position = SIMD3(0, 0.12, 0)
        head.addChild(headEntity)
        shoulders.addChild(head)

        // Arms
        buildArm(
            side: -1,
            upperArm: upperArmL,
            forearm: forearmL,
            hand: handL,
            skinMat: skinMat,
            into: shoulders
        )
        buildArm(
            side: 1,
            upperArm: upperArmR,
            forearm: forearmR,
            hand: handR,
            skinMat: skinMat,
            into: shoulders
        )

        // Legs
        buildLeg(
            side: -1,
            thigh: thighL,
            shin: shinL,
            foot: footL,
            kitDarkMat: kitDarkMat,
            shoeMat: shoeMat,
            into: pelvis
        )
        buildLeg(
            side: 1,
            thigh: thighR,
            shin: shinR,
            foot: footR,
            kitDarkMat: kitDarkMat,
            shoeMat: shoeMat,
            into: pelvis
        )
    }

    // MARK: - Arm Construction

    private func buildArm(
        side: Float,
        upperArm: Entity,
        forearm: Entity,
        hand: Entity,
        skinMat: SimpleMaterial,
        into parent: Entity
    ) {
        let upperArmLength: Float = 0.30
        let forearmLength: Float = 0.28

        // Upper arm pivot at shoulder
        upperArm.position = SIMD3(side * 0.18, 0, 0)
        let upperModel = ModelEntity(
            mesh: MeshResource.generateCylinder(height: upperArmLength, radius: 0.025),
            materials: [skinMat]
        )
        upperModel.position = SIMD3(0, -upperArmLength / 2, 0)
        upperModel.name = "upperArm-model-\(side > 0 ? "R" : "L")"
        upperArm.addChild(upperModel)
        parent.addChild(upperArm)

        // Forearm pivot at elbow
        forearm.position = SIMD3(0, -upperArmLength, 0)
        let forearmModel = ModelEntity(
            mesh: MeshResource.generateCylinder(height: forearmLength, radius: 0.022),
            materials: [skinMat]
        )
        forearmModel.position = SIMD3(0, -forearmLength / 2, 0)
        forearmModel.name = "forearm-model-\(side > 0 ? "R" : "L")"
        forearm.addChild(forearmModel)
        upperArm.addChild(forearm)

        // Hand at wrist
        let handEntity = ReplayMeshFactory.handEntity(material: skinMat)
        handEntity.position = SIMD3(0, -forearmLength, 0)
        hand.addChild(handEntity)
        forearm.addChild(hand)
    }

    // MARK: - Leg Construction

    private func buildLeg(
        side: Float,
        thigh: Entity,
        shin: Entity,
        foot: Entity,
        kitDarkMat: SimpleMaterial,
        shoeMat: SimpleMaterial,
        into parent: Entity
    ) {
        let thighLength: Float = 0.42
        let shinLength: Float = 0.40

        // Thigh pivot at hip
        thigh.position = SIMD3(side * 0.10, 0, 0)
        let thighModel = ModelEntity(
            mesh: MeshResource.generateCylinder(height: thighLength, radius: 0.04),
            materials: [kitDarkMat]
        )
        thighModel.position = SIMD3(0, -thighLength / 2, 0)
        thighModel.name = "thigh-model-\(side > 0 ? "R" : "L")"
        thigh.addChild(thighModel)
        parent.addChild(thigh)

        // Shin pivot at knee
        shin.position = SIMD3(0, -thighLength, 0)
        let shinModel = ModelEntity(
            mesh: MeshResource.generateCylinder(height: shinLength, radius: 0.032),
            materials: [kitDarkMat]
        )
        shinModel.position = SIMD3(0, -shinLength / 2, 0)
        shinModel.name = "shin-model-\(side > 0 ? "R" : "L")"
        shin.addChild(shinModel)
        thigh.addChild(shin)

        // Foot at ankle
        let footEntity = ReplayMeshFactory.footEntity(material: shoeMat)
        footEntity.position = SIMD3(0, -shinLength, 0)
        foot.addChild(footEntity)
        shin.addChild(foot)
    }

    // MARK: - Pose Application

    /// Apply a common athlete joint pose to the hierarchy.
    /// All joint values pass through a finite guard before reaching RealityKit.
    func applyPose(_ pose: ReplayAthleteJointPose) {
        // Torso lean (rotate around X axis)
        torso.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(pose.torsoLean), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )
        // Torso tilt (rotate around Z axis)
        let tiltQuat = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(pose.torsoTilt), fallback: 0),
            axis: SIMD3(0, 0, 1)
        )
        torso.orientation = tiltQuat * torso.orientation

        // Head pitch
        head.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(pose.headPitch), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )

        // Shoulders (flex = rotation around X axis)
        shoulders.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float((pose.shoulderFlexL + pose.shoulderFlexR) / 2), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )

        // Arms
        applyArmPose(
            upperArm: upperArmL,
            forearm: forearmL,
            shoulderFlex: pose.shoulderFlexL,
            elbowFlex: pose.elbowFlexL
        )
        applyArmPose(
            upperArm: upperArmR,
            forearm: forearmR,
            shoulderFlex: pose.shoulderFlexR,
            elbowFlex: pose.elbowFlexR
        )

        // Legs
        applyLegPose(
            thigh: thighL,
            shin: shinL,
            hipFlex: pose.hipFlexL,
            kneeFlex: pose.kneeFlexL
        )
        applyLegPose(
            thigh: thighR,
            shin: shinR,
            hipFlex: pose.hipFlexR,
            kneeFlex: pose.kneeFlexR
        )
    }

    private func applyArmPose(
        upperArm: Entity,
        forearm: Entity,
        shoulderFlex: Double,
        elbowFlex: Double
    ) {
        upperArm.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(shoulderFlex), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )
        forearm.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(-elbowFlex), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )
    }

    private func applyLegPose(
        thigh: Entity,
        shin: Entity,
        hipFlex: Double,
        kneeFlex: Double
    ) {
        thigh.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(hipFlex), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )
        shin.orientation = simd_quatf(
            angle: ReplaySportRigFiniteGuard.finite(Float(-kneeFlex), fallback: 0),
            axis: SIMD3(1, 0, 0)
        )
    }

    // MARK: - Finite Check

    /// Verify all entity transforms are finite. Returns false if any are not.
    func hasFiniteTransforms() -> Bool {
        let entities = [
            pelvis, torso, shoulders, head,
            upperArmL, forearmL, handL,
            upperArmR, forearmR, handR,
            thighL, shinL, footL,
            thighR, shinR, footR,
        ]
        for entity in entities {
            let p = entity.position
            let o = entity.orientation
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { return false }
            if !o.vector.x.isFinite || !o.vector.y.isFinite
                || !o.vector.z.isFinite || !o.vector.w.isFinite { return false }
        }
        return true
    }
}
