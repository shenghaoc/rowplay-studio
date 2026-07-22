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

    // Athlete — either the lightweight procedural body or the V4 USDZ instance.
    private let athlete = ReplayAthleteRig()
    private var canonicalAthlete: ReplayAthleteInstance?
    private var poseAdapter: ReplayAthletePoseAdapter?

    /// Build-time handle orientation (Z rotation to lay cylinder horizontal).
    private let handleBaseOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

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

        // Hull — narrow shell
        hull.name = "hull"
        if visualProvider?.attachVisual(named: "visual-hull", to: hull) != true {
            let hullMesh = MeshResource.generateBox(size: SIMD3(0.5, 0.2, 3.0))
            let hullModel = ModelEntity(mesh: hullMesh, materials: [accentMat])
            hullModel.name = "hull-model"
            hull.addChild(hullModel)
        }
        hull.position = SIMD3(0, 0.15, 0)
        root.addChild(hull)

        // Deck stripe
        let stripe = Entity()
        stripe.name = "deck-stripe"
        if visualProvider?.attachVisual(named: "visual-deck-stripe", to: stripe) != true {
            let stripeMesh = MeshResource.generateBox(size: SIMD3(0.14, 0.015, 2.2))
            let stripeMat = SimpleMaterial(
                color: NSColor.white.withAlphaComponent(CGFloat(opacity)),
                isMetallic: false
            )
            let stripeModel = ModelEntity(mesh: stripeMesh, materials: [stripeMat])
            stripeModel.name = "deck-stripe-model"
            stripe.addChild(stripeModel)
        }
        stripe.position = SIMD3(0, 0.335, 0)
        root.addChild(stripe)

        // Footplate
        let footplate = Entity()
        footplate.name = "footplate"
        if visualProvider?.attachVisual(named: "visual-footplate", to: footplate) != true {
            let footplateMesh = MeshResource.generateBox(size: SIMD3(0.48, 0.05, 0.12))
            let footplateModel = ModelEntity(mesh: footplateMesh, materials: [metalMat])
            footplateModel.name = "footplate-model"
            footplate.addChild(footplateModel)
        }
        footplate.position = SIMD3(0, 0.34, 0.72)
        footAnchorL.name = "foot-anchor-L"
        footAnchorL.position = SIMD3(-0.1, 0.03, 0)
        footplate.addChild(footAnchorL)
        footAnchorR.name = "foot-anchor-R"
        footAnchorR.position = SIMD3(0.1, 0.03, 0)
        footplate.addChild(footAnchorR)
        root.addChild(footplate)

        // Rail
        let rail = Entity()
        rail.name = "rail"
        if visualProvider?.attachVisual(named: "visual-rail", to: rail) != true {
            let railMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.04, 2.8))
            let railModel = ModelEntity(mesh: railMesh, materials: [metalMat])
            railModel.name = "rail-model"
            rail.addChild(railModel)
        }
        rail.position = SIMD3(0, 0.26, 0)
        root.addChild(rail)

        // Seat
        seat.name = "seat"
        if visualProvider?.attachVisual(named: "visual-seat", to: seat) != true {
            let seatMesh = MeshResource.generateBox(size: SIMD3(0.25, 0.06, 0.20))
            let seatMat = SimpleMaterial(
                color: NSColor.gray.withAlphaComponent(CGFloat(opacity)),
                isMetallic: false
            )
            let seatModel = ModelEntity(mesh: seatMesh, materials: [seatMat])
            seatModel.name = "seat-model"
            seat.addChild(seatModel)
        }
        seat.position = SIMD3(0, 0.30, -0.2)
        root.addChild(seat)

        // Handle — cylinder laid horizontal via base orientation
        handle.name = "handle"
        if visualProvider?.attachVisual(named: "visual-handle", to: handle) != true {
            let handleMesh = MeshResource.generateCylinder(height: 0.5, radius: 0.015)
            let handleModel = ModelEntity(mesh: handleMesh, materials: [metalMat])
            handleModel.name = "handle-model"
            handle.addChild(handleModel)
        }
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
            let visualName = side > 0 ? "visual-oar-starboard" : "visual-oar-port"
            if visualProvider?.attachVisual(named: visualName, to: oar) != true {
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
            }

            // The oar entity origin is the gate, so sweep/feather rotations
            // cannot translate the collar away from its fixed hull contact.
            oar.position = SIMD3(side * 0.32, 0.24, 0)
            root.addChild(oar)
            oars.append(oar)
        }

        // Athlete body (seated). Canonical V4 and procedural paths are exclusive.
        if let canonicalAthlete {
            self.canonicalAthlete = canonicalAthlete
            self.poseAdapter = ReplayAthletePoseAdapter(contract: canonicalAthlete.contract)
            canonicalAthlete.attach(to: root)
            // USDZ root orientation differs from native pivot space; scale and
            // place so the hips sit on the seat in local rig coordinates.
            canonicalAthlete.root.scale = SIMD3(repeating: 0.95)
            canonicalAthlete.root.position = SIMD3(0, 0.30, -0.1)
        } else {
            athlete.build(
                into: root,
                seated: true,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = SIMD3(0, 0.30, -0.1)
        }
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose, motion: ReplayAthleteMotionSample?) {
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

        let pelvisTarget = SIMD3<Float>(0, 0.30, -0.1 + seatZ)
        let handL = handleGripL.position(relativeTo: root)
        let handR = handleGripR.position(relativeTo: root)
        let footL = footAnchorL.position(relativeTo: root)
        let footR = footAnchorR.position(relativeTo: root)

        if let canonicalAthlete, let poseAdapter, let motion {
            poseAdapter.apply(sample: motion, sport: .rower, to: canonicalAthlete)
            _ = ReplayAthleteContactSolver.constrain(
                instance: canonicalAthlete,
                targets: ReplayAthleteContactTargets(
                    pelvis: pelvisTarget,
                    leftHand: handL,
                    rightHand: handR,
                    leftFoot: footL,
                    rightFoot: footR
                ),
                relativeTo: root
            )
        } else {
            athlete.pelvis.position = pelvisTarget
            athlete.applyPose(rowerPose.joints)
            athlete.handL.setPosition(handL, relativeTo: root)
            athlete.handR.setPosition(handR, relativeTo: root)
            athlete.footL.setPosition(footL, relativeTo: root)
            athlete.footR.setPosition(footR, relativeTo: root)
        }
    }
}
