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
    private let handleGripL = Entity()
    private let handleGripR = Entity()
    private let footAnchorL = Entity()
    private let footAnchorR = Entity()
    private var oars: [Entity] = []

    // Athlete
    private let athlete = ReplayAthleteRig()

    /// Build-time handle orientation (Z rotation to lay cylinder horizontal).
    private let handleBaseOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

    // MARK: - Build

    func build(into parent: ModelEntity, accent: Color, opacity: Float, meshes: [String: Entity]? = nil) {
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

        // Hull — narrow shell
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
        footAnchorL.name = "foot-anchor-L"
        footAnchorL.position = SIMD3(-0.1, 0.03, 0)
        footplate.addChild(footAnchorL)
        footAnchorR.name = "foot-anchor-R"
        footAnchorR.position = SIMD3(0.1, 0.03, 0)
        footplate.addChild(footAnchorR)
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

        // Handle — cylinder laid horizontal via base orientation
        handle.name = "handle"
        let handleMesh = MeshResource.generateCylinder(height: 0.5, radius: 0.015)
        let handleModel = ModelEntity(mesh: handleMesh, materials: [metalMat])
        handleModel.name = "handle-model"
        handle.addChild(handleModel)
        handleGripL.name = "handle-grip-anchor-L"
        handleGripL.position = SIMD3(0, 0.18, 0)
        handle.addChild(handleGripL)
        handleGripR.name = "handle-grip-anchor-R"
        handleGripR.position = SIMD3(0, -0.18, 0)
        handle.addChild(handleGripR)
        handle.position = SIMD3(0, 0.55, 0.6)
        handle.orientation = handleBaseOrientation
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
            collar.name = "collar"
            oar.addChild(collar)

            // Blade
            let bladeMesh = MeshResource.generateBox(size: SIMD3(0.5, 0.02, 0.26))
            let blade = ModelEntity(mesh: bladeMesh, materials: [accentMat])
            blade.position = SIMD3(side * 2.4, -0.05, 0)
            blade.name = "blade"
            oar.addChild(blade)

            // The oar entity origin is the gate, so sweep/feather rotations
            // cannot translate the collar away from its fixed hull contact.
            oar.position = SIMD3(side * 0.32, 0.24, 0)
            root.addChild(oar)
            oars.append(oar)
        }

        // Athlete body (seated)
        athlete.build(into: root, seated: true, accent: accent, opacity: opacity, meshes: meshes)
        // Position the pelvis on the seat
        athlete.pelvis.position = SIMD3(0, 0.30, -0.1)
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose) {
        guard case .rower(let rowerPose) = pose else {
            assertionFailure("ReplayRowerRig.applyPose received non-rower pose")
            return
        }

        // Finite guard at Studio/RealityKit boundary
        let seatZ = ReplaySportRigFiniteGuard.finite(Float(rowerPose.seatZ), fallback: -0.1)
        let handleY = ReplaySportRigFiniteGuard.finite(Float(rowerPose.handleY), fallback: 0.55)
        let handleZ = ReplaySportRigFiniteGuard.finite(Float(rowerPose.handleZ), fallback: 0.6)
        let handleRotX = ReplaySportRigFiniteGuard.finite(Float(rowerPose.handleRotX), fallback: 0)
        let oarSweep = ReplaySportRigFiniteGuard.finite(Float(rowerPose.oarSweep), fallback: 0)
        let oarFeather = ReplaySportRigFiniteGuard.finite(Float(rowerPose.oarFeather), fallback: -0.06)

        // Seat slides along rail
        seat.position.z = Float(-0.2) + seatZ

        // Handle moves with stroke — compose feather rotation on top of base orientation
        handle.position = SIMD3(0, handleY, handleZ)
        handle.orientation = simd_quatf(angle: handleRotX, axis: SIMD3(1, 0, 0)) * handleBaseOrientation

        // Oars sweep and feather
        for (i, oar) in oars.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            oar.orientation = simd_quatf(
                angle: oarSweep * side,
                axis: SIMD3(0, 1, 0)
            ) * simd_quatf(
                angle: oarFeather * side,
                axis: SIMD3(1, 0, 0)
            )
        }

        // Pelvis follows seat
        athlete.pelvis.position = SIMD3(0, 0.30, -0.1 + seatZ)

        // Apply athlete joint pose (with finite guard inside)
        athlete.applyPose(rowerPose.joints)

        // Preserve equipment contact at the terminal joints.
        athlete.handL.setPosition(handleGripL.position(relativeTo: root), relativeTo: root)
        athlete.handR.setPosition(handleGripR.position(relativeTo: root), relativeTo: root)
        athlete.footL.setPosition(footAnchorL.position(relativeTo: root), relativeTo: root)
        athlete.footR.setPosition(footAnchorR.position(relativeTo: root), relativeTo: root)
    }
}
