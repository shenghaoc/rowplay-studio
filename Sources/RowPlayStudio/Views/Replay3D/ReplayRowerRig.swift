import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// RowErg articulated rig: a sculling shell, independent port/starboard
/// sculls, sliding seat, and athlete body.
///
/// Contact invariants:
/// - Each hand remains on its own inboard scull grip
/// - Feet remain at the contract-defined stretcher contacts
/// - Pelvis remains on the sliding seat
/// - Both sculls pivot from the fixed contract-defined oarlocks
@MainActor
final class ReplayRowerRig: ReplaySportRig {
    let root = Entity()

    private struct Scull {
        let side: Float
        let pivot: Entity
        let blade: Entity
        let gripAnchor: Entity
    }

    private let boat = Entity()
    private let seat = Entity()
    private let footAnchorL = Entity()
    private let footAnchorR = Entity()
    private var sculls: [Scull] = []

    // Fixed once during build; pose application never crosses source paths.
    private var source: ReplayRigSource?
    private var canonicalRuntimeFailure = false

    private let seatBasePosition = SIMD3<Float>(0, 0.30, -0.2)
    private let scullInboardContact: Float = 0.66
        + Float(ReplayRowGripContract.scullGrip.length) / 2
        - Float(ReplayRowGripContract.scullGrip.anchorFromEnd)

    // MARK: - Build

    func build(
        into parent: ModelEntity,
        accent: Color,
        opacity: Float,
        visualProvider: (any ReplayRigVisualProvider)? = nil,
        canonicalAthlete: ReplayAthleteInstance? = nil
    ) {
        root.name = "rower-rig"
        parent.addChild(root)

        let accentMat = ReplayMeshFactory.accentMaterial(accent, opacity: opacity)
        let metalMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.15, alpha: 1),
            opacity: opacity
        )
        let oarMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.94, alpha: 1),
            opacity: opacity
        )

        boat.name = "boat"
        if visualProvider?.attachVisual(named: "visual-boat", to: boat) != true {
            buildProceduralBoat(
                into: boat,
                accentMaterial: accentMat,
                metalMaterial: metalMat,
                opacity: opacity
            )
        }
        root.addChild(boat)

        seat.name = "seat"
        if visualProvider?.attachVisual(named: "visual-seat", to: seat) != true {
            let mesh = MeshResource.generateBox(size: SIMD3(0.31, 0.055, 0.24))
            let material = SimpleMaterial(
                color: NSColor.gray.withAlphaComponent(CGFloat(opacity)),
                isMetallic: false
            )
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "seat-model"
            seat.addChild(model)
        }
        seat.position = seatBasePosition
        root.addChild(seat)

        let foot = ReplayRowGripContract.footContact
        footAnchorL.name = "foot-anchor-L"
        footAnchorL.position = SIMD3(-Float(foot.lateral), Float(foot.y), Float(foot.z))
        root.addChild(footAnchorL)
        footAnchorR.name = "foot-anchor-R"
        footAnchorR.position = SIMD3(Float(foot.lateral), Float(foot.y), Float(foot.z))
        root.addChild(footAnchorR)

        for side: Float in [-1, 1] {
            sculls.append(buildScull(
                side: side,
                accentMaterial: accentMat,
                metalMaterial: metalMat,
                oarMaterial: oarMat,
                visualProvider: visualProvider
            ))
        }

        // Athlete body (seated). Canonical V4 and procedural paths are exclusive.
        if let canonicalAthlete {
            source = .bundled(ReplayBundledAthleteRuntime(
                instance: canonicalAthlete,
                sport: .rower,
                parent: root,
                rootScale: 1.0,
                rootPosition: SIMD3(0, 0.30, -0.1)
            ))
        } else {
            let athlete = ReplayAthleteRig()
            athlete.build(
                into: root,
                seated: true,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = SIMD3(0, 0.30, -0.1)
            source = .procedural(athlete)
        }
    }

    private func buildProceduralBoat(
        into parent: Entity,
        accentMaterial: any RealityKit.Material,
        metalMaterial: any RealityKit.Material,
        opacity: Float
    ) {
        let hull = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.50, 0.20, 3.0)),
            materials: [accentMaterial]
        )
        hull.name = "hull"
        hull.position = SIMD3(0, 0.15, 0)
        parent.addChild(hull)

        let stripeMaterial = SimpleMaterial(
            color: NSColor.white.withAlphaComponent(CGFloat(opacity)),
            isMetallic: false
        )
        let stripe = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.14, 0.015, 2.2)),
            materials: [stripeMaterial]
        )
        stripe.name = "deck-stripe"
        stripe.position = SIMD3(0, 0.335, 0)
        parent.addChild(stripe)

        let stretcher = ReplayRowGripContract.stretcher
        let footplate = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.48, 0.05, 0.12)),
            materials: [metalMaterial]
        )
        footplate.name = "footplate"
        footplate.position = SIMD3(0, Float(stretcher.centerY), Float(stretcher.centerZ))
        footplate.orientation = simd_quatf(
            angle: Float(stretcher.boardRotation),
            axis: SIMD3(1, 0, 0)
        )
        parent.addChild(footplate)

        let rail = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.06, 0.04, 2.8)),
            materials: [metalMaterial]
        )
        rail.name = "rail"
        rail.position = SIMD3(0, 0.26, 0)
        parent.addChild(rail)
    }

    private func buildScull(
        side: Float,
        accentMaterial: any RealityKit.Material,
        metalMaterial: any RealityKit.Material,
        oarMaterial: any RealityKit.Material,
        visualProvider: (any ReplayRigVisualProvider)?
    ) -> Scull {
        let suffix = side > 0 ? "starboard" : "port"
        let shortSuffix = side > 0 ? "R" : "L"
        let pivot = Entity()
        pivot.name = "oar-\(suffix)"

        let visualRoot = Entity()
        visualRoot.name = "oar-visual-\(shortSuffix)"
        // The authored oar points +X outboard. Mirror the port visual around
        // its oarlock while leaving the logical contact solve symmetric.
        if side < 0 {
            visualRoot.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        }

        let oarVisualName = side > 0 ? "visual-oar-starboard" : "visual-oar-port"
        if visualProvider?.attachVisual(named: oarVisualName, to: visualRoot) != true {
            let shaft = ModelEntity(
                mesh: .generateCylinder(height: 2.22, radius: 0.02),
                materials: [oarMaterial]
            )
            shaft.name = "shaft"
            shaft.position = SIMD3(0.61, 0, -0.04)
            shaft.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            visualRoot.addChild(shaft)

            let grip = ModelEntity(
                mesh: .generateCylinder(
                    height: Float(ReplayRowGripContract.scullGrip.length),
                    radius: Float(ReplayRowGripContract.scullGrip.radius)
                ),
                materials: [metalMaterial]
            )
            grip.name = "scull-grip-\(shortSuffix)"
            grip.position = SIMD3(-0.66, 0, -0.04)
            grip.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            visualRoot.addChild(grip)

            let collar = ModelEntity(
                mesh: .generateSphere(radius: 0.05),
                materials: [metalMaterial]
            )
            collar.name = "collar"
            visualRoot.addChild(collar)
        }

        let blade = Entity()
        blade.name = "blade-\(shortSuffix)"
        let bladeVisualName = side > 0 ? "visual-blade-starboard" : "visual-blade-port"
        if visualProvider?.attachFittedVisual(
            named: bladeVisualName,
            to: blade,
            targetSize: SIMD3(0.54, 0.022, 0.30)
        ) != true {
            let model = ModelEntity(
                mesh: .generateBox(size: SIMD3(0.54, 0.022, 0.30)),
                materials: [accentMaterial]
            )
            model.name = "blade-model-\(shortSuffix)"
            blade.addChild(model)
        }
        blade.position = SIMD3(1.82, -0.06, 0)
        visualRoot.addChild(blade)
        pivot.addChild(visualRoot)

        let gripAnchor = Entity()
        gripAnchor.name = "scull-grip-anchor-\(shortSuffix)"
        gripAnchor.position = SIMD3(-side * scullInboardContact, -0.04, 0)
        pivot.addChild(gripAnchor)

        let oarlock = ReplayRowGripContract.oarlock
        pivot.position = SIMD3(
            side * Float(oarlock.lateral),
            Float(oarlock.y),
            Float(oarlock.z)
        )
        root.addChild(pivot)
        return Scull(side: side, pivot: pivot, blade: blade, gripAnchor: gripAnchor)
    }

    // MARK: - Pose Application

    @discardableResult
    func applyPose(
        _ pose: ReplaySportRigPose,
        motion: ReplayAthleteMotionSample?
    ) -> ReplaySportRigPoseResult {
        guard case .rower(let rowerPose) = pose else {
            assertionFailure("ReplayRowerRig.applyPose received non-rower pose")
            return .failed(.unexpectedSport)
        }

        let seatZ = ReplaySportRigFiniteGuard.finite(Float(rowerPose.seatZ), fallback: -0.1)
        let oarSweep = ReplaySportRigFiniteGuard.finite(Float(rowerPose.oarSweep), fallback: 0)
        let oarFeather = ReplaySportRigFiniteGuard.finite(Float(rowerPose.oarFeather), fallback: -0.06)

        seat.position = seatBasePosition + SIMD3(0, 0, seatZ)

        for scull in sculls {
            // Yaw moves each inboard grip on its own rigid circle. Roll is
            // mirrored so both blades bury/extract together without moving
            // either oarlock.
            let yaw = simd_quatf(angle: oarSweep * scull.side, axis: SIMD3(0, 1, 0))
            let roll = simd_quatf(angle: -oarFeather * scull.side, axis: SIMD3(0, 0, 1))
            scull.pivot.orientation = roll * yaw
            scull.blade.orientation = simd_quatf(
                angle: Float(rowerPose.handleRotX),
                axis: SIMD3(1, 0, 0)
            )
        }

        let pelvisTarget = SIMD3<Float>(0, 0.30, -0.1 + seatZ)
        let handL = sculls[0].gripAnchor.position(relativeTo: root)
        let handR = sculls[1].gripAnchor.position(relativeTo: root)
        let footL = footAnchorL.position(relativeTo: root)
        let footR = footAnchorR.position(relativeTo: root)

        let targets = ReplayAthleteContactTargets(
            pelvis: pelvisTarget,
            leftHand: handL,
            rightHand: handR,
            leftFoot: footL,
            rightFoot: footR
        )
        switch source {
        case .bundled(let runtime):
            let result = runtime.apply(motion: motion, targets: targets, relativeTo: root)
            canonicalRuntimeFailure = result.failure != nil
            return result
        case .procedural(let athlete):
            athlete.pelvis.position = pelvisTarget
            athlete.applyPose(rowerPose.joints)
            athlete.handL.setPosition(handL, relativeTo: root)
            athlete.handR.setPosition(handR, relativeTo: root)
            athlete.footL.setPosition(footL, relativeTo: root)
            athlete.footR.setPosition(footR, relativeTo: root)
            return .applied
        case nil:
            return .failed(.motionSampleRejected)
        }
    }

    func applyGhostTranslucency() {
        ReplayRigAppearancePolicy.applyRivalEquipment(
            to: root,
            excludingAthlete: source?.bundledAthlete?.athleteEntity
        )
    }

    func consumeCanonicalRuntimeFailure() -> Bool {
        defer { canonicalRuntimeFailure = false }
        return canonicalRuntimeFailure
    }
}
