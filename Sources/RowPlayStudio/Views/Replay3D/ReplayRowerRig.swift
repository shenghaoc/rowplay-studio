import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// RowErg articulated rig: scull hull, seat, handle, oars, and athlete body.
///
/// Contact invariants:
/// - Hands remain on the handle
/// - Feet remain at the footplate
/// - Pelvis remains on the seat
/// - Both oars pivot from stable gates
@MainActor
final class ReplayRowerRig: ReplaySportRig {
    let root = Entity()

    // Machine parts
    private let hull = Entity()
    private let seat = Entity()
    private let handle = Entity()
    private var oars: [Entity] = []

    // Athlete
    private let athlete = ReplayAthleteRig()

    // Pose state for drift detection
    private var lastPose: RowerRigPose?

    // MARK: - Build

    func build(into parent: ModelEntity, accent: Color, opacity: Float) {
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

        // Hull — narrow capsule shell
        hull.name = "hull"
        let hullMesh = MeshResource.generateBox(size: SIMD3(0.5, 0.2, 3.0))
        let hullModel = ModelEntity(mesh: hullMesh, materials: [accentMat])
        hullModel.name = "hull-model"
        hull.addChild(hullModel)
        hull.position = SIMD3(0, 0.15, 0)
        root.addChild(hull)

        // Deck stripe
        let stripeMesh = MeshResource.generateBox(size: SIMD3(0.14, 0.015, 2.2))
        let stripeMat = SimpleMaterial(
            color: NSColor.white.withAlphaComponent(CGFloat(opacity)),
            isMetallic: false
        )
        let stripe = ModelEntity(mesh: stripeMesh, materials: [stripeMat])
        stripe.name = "deck-stripe"
        stripe.position = SIMD3(0, 0.335, 0)
        root.addChild(stripe)

        // Footplate
        let footplateMesh = MeshResource.generateBox(size: SIMD3(0.48, 0.05, 0.12))
        let footplate = ModelEntity(mesh: footplateMesh, materials: [metalMat])
        footplate.name = "footplate"
        footplate.position = SIMD3(0, 0.34, 0.72)
        root.addChild(footplate)

        // Rail
        let railMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.04, 2.8))
        let rail = ModelEntity(mesh: railMesh, materials: [metalMat])
        rail.name = "rail"
        rail.position = SIMD3(0, 0.26, 0)
        root.addChild(rail)

        // Seat
        seat.name = "seat"
        let seatMesh = MeshResource.generateBox(size: SIMD3(0.25, 0.06, 0.20))
        let seatMat = SimpleMaterial(
            color: NSColor.gray.withAlphaComponent(CGFloat(opacity)),
            
            isMetallic: false
        )
        let seatModel = ModelEntity(mesh: seatMesh, materials: [seatMat])
        seatModel.name = "seat-model"
        seat.addChild(seatModel)
        seat.position = SIMD3(0, 0.30, -0.2)
        root.addChild(seat)

        // Handle
        handle.name = "handle"
        let handleMesh = MeshResource.generateCylinder(height: 0.5, radius: 0.015)
        let handleModel = ModelEntity(mesh: handleMesh, materials: [metalMat])
        handleModel.name = "handle-model"
        handle.addChild(handleModel)
        handle.position = SIMD3(0, 0.55, 0.6)
        handle.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        root.addChild(handle)

        // Oars
        for side: Float in [-1, 1] {
            let oar = Entity()
            oar.name = "oar-\(side > 0 ? "starboard" : "port")"

            // Shaft
            let shaftMesh = MeshResource.generateCylinder(height: 2.4, radius: 0.02)
            let shaft = ModelEntity(mesh: shaftMesh, materials: [oarMat])
            shaft.position = SIMD3(side * 1.2, 0, 0)
            shaft.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            shaft.name = "shaft"
            oar.addChild(shaft)

            // Collar
            let collarMesh = MeshResource.generateSphere(radius: 0.05)
            let collar = ModelEntity(mesh: collarMesh, materials: [metalMat])
            collar.position = SIMD3(side * 1.9, 0, 0)
            collar.name = "collar"
            oar.addChild(collar)

            // Blade
            let bladeMesh = MeshResource.generateBox(size: SIMD3(0.5, 0.02, 0.26))
            let blade = ModelEntity(mesh: bladeMesh, materials: [accentMat])
            blade.position = SIMD3(side * 2.4, -0.05, 0)
            blade.name = "blade"
            oar.addChild(blade)

            oar.position = SIMD3(0, 0.24, 0)
            root.addChild(oar)
            oars.append(oar)
        }

        // Athlete body (seated)
        athlete.build(into: root, seated: true, accent: accent, opacity: opacity)
        // Position the pelvis on the seat
        athlete.pelvis.position = SIMD3(0, 0.30, -0.1)
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose, reduceMotion: Bool) {
        guard case .rower(let rowerPose) = pose else { return }

        // Seat slides along rail
        seat.position.z = Float(-0.2 + rowerPose.seatZ)

        // Handle moves with stroke
        handle.position = SIMD3(
            0,
            Float(rowerPose.handleY),
            Float(rowerPose.handleZ)
        )
        handle.orientation = simd_quatf(
            angle: Float(rowerPose.handleRotX),
            axis: SIMD3(1, 0, 0)
        )

        // Oars sweep and feather
        for (i, oar) in oars.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            oar.orientation = simd_quatf(
                angle: Float(rowerPose.oarSweep) * side,
                axis: SIMD3(0, 1, 0)
            ) * simd_quatf(
                angle: Float(rowerPose.oarFeather) * side,
                axis: SIMD3(0, 0, 1)
            )
        }

        // Pelvis follows seat
        athlete.pelvis.position = SIMD3(0, 0.30, Float(-0.1 + rowerPose.seatZ))

        // Apply athlete joint pose
        athlete.applyPose(rowerPose.joints)

        lastPose = rowerPose
    }

    // MARK: - Ghost Translucency

    func applyGhostTranslucency() {
        applyTranslucency(to: root, opacity: 0.45)
    }

    private func applyTranslucency(to entity: Entity, opacity: Float) {
        if let model = entity as? ModelEntity {
            model.model?.materials = model.model?.materials.map { mat in
                if var sm = mat as? SimpleMaterial {
                    let c = sm.color.tint
                    sm.color = .init(tint: c.withAlphaComponent(CGFloat(opacity)))
                    return sm
                }
                return mat
            } ?? []
        }
        for child in entity.children {
            applyTranslucency(to: child, opacity: opacity)
        }
    }
}
