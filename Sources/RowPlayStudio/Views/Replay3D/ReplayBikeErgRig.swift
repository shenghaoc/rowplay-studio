import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// BikeErg articulated rig: wheels, frame, cranks, handlebar, and rider body.
///
/// Contact invariants:
/// - Hands remain on handlebar
/// - Pelvis remains on saddle
/// - Each foot remains on its pedal (opposite pedals throughout crank cycle)
@MainActor
final class ReplayBikeErgRig: ReplaySportRig {
    let root = Entity()

    // Machine parts
    private var wheels: [Entity] = []
    private let cranks = Entity()
    private let saddle = Entity()

    // Rider group (contains athlete body)
    private let rider = Entity()

    // Athlete
    private let athlete = ReplayAthleteRig()

    // Pedal references for foot attachment
    private let pedalL = Entity()
    private let pedalR = Entity()

    // Pose state for drift detection
    private var lastPose: BikeErgRigPose?

    // MARK: - Build

    func build(into parent: ModelEntity, accent: Color, opacity: Float) {
        root.name = "bikeerg-rig"
        parent.addChild(root)

        let accentMat = ReplayMeshFactory.accentMaterial(accent, opacity: opacity)
        let frameMat = accentMat
        let tyreMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1),
            
            opacity: opacity
        )
        let spokeMat = accentMat
        let metalMat = ReplayMeshFactory.metalMaterial(
            NSColor.gray,
            
            opacity: opacity
        )
        let darkMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
            
            opacity: opacity
        )

        let wheelR: Float = 0.45

        // Wheels (proper torus + spokes)
        for z: Float in [0.85, -0.85] {
            let wheel = ReplayMeshFactory.wheelEntity(
                radius: wheelR,
                tyreMaterial: tyreMat,
                spokeMaterial: spokeMat
            )
            wheel.name = "wheel-\(z > 0 ? "front" : "rear")"
            wheel.position = SIMD3(0, wheelR, z)
            root.addChild(wheel)
            wheels.append(wheel)
        }

        // Frame: down tube, seat tube, top tube, chain stays
        let downTubeMesh = MeshResource.generateBox(size: SIMD3(0.08, 0.08, 1.6))
        let downTube = ModelEntity(mesh: downTubeMesh, materials: [frameMat])
        downTube.name = "downTube"
        downTube.position = SIMD3(0, wheelR + 0.15, 0)
        root.addChild(downTube)

        let seatTubeMesh = MeshResource.generateBox(size: SIMD3(0.08, 0.7, 0.08))
        let seatTube = ModelEntity(mesh: seatTubeMesh, materials: [frameMat])
        seatTube.name = "seatTube"
        seatTube.position = SIMD3(0, wheelR + 0.45, -0.4)
        root.addChild(seatTube)

        let topTubeMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 1.1))
        let topTube = ModelEntity(mesh: topTubeMesh, materials: [frameMat])
        topTube.name = "topTube"
        topTube.position = SIMD3(0, wheelR + 0.75, -0.15)
        root.addChild(topTube)

        // Chain stays
        for side: Float in [-1, 1] {
            let stayMesh = MeshResource.generateBox(size: SIMD3(0.03, 0.03, 0.85))
            let stay = ModelEntity(mesh: stayMesh, materials: [frameMat])
            stay.name = "chainStay-\(side > 0 ? "R" : "L")"
            stay.position = SIMD3(side * 0.06, wheelR + 0.05, 0.4)
            root.addChild(stay)
        }

        // Saddle
        saddle.name = "saddle"
        let saddleMesh = MeshResource.generateBox(size: SIMD3(0.18, 0.05, 0.30))
        let saddleMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)
        let saddleModel = ModelEntity(mesh: saddleMesh, materials: [saddleMat])
        saddleModel.name = "saddle-model"
        saddle.addChild(saddleModel)
        saddle.position = SIMD3(0, wheelR + 0.8, -0.4)
        root.addChild(saddle)

        // Cranks with chain ring and pedals
        cranks.name = "cranks"
        cranks.position = SIMD3(0, wheelR, -0.05)

        // Chain ring
        let chainRingMesh = MeshResource.generateSphere(radius: 0.16)
        let chainRing = ModelEntity(mesh: chainRingMesh, materials: [metalMat])
        chainRing.name = "chainRing"
        chainRing.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        cranks.addChild(chainRing)

        // Pedals
        let pedalMesh = MeshResource.generateBox(size: SIMD3(0.22, 0.05, 0.10))
        let pedalMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)

        pedalL.name = "pedal-L"
        let pedalLModel = ModelEntity(mesh: pedalMesh, materials: [pedalMat])
        pedalLModel.name = "pedal-model-L"
        pedalL.addChild(pedalLModel)
        pedalL.position = SIMD3(-0.1, -0.18, 0)
        cranks.addChild(pedalL)

        pedalR.name = "pedal-R"
        let pedalRModel = ModelEntity(mesh: pedalMesh, materials: [pedalMat])
        pedalRModel.name = "pedal-model-R"
        pedalR.addChild(pedalRModel)
        pedalR.position = SIMD3(0.1, 0.18, 0)
        cranks.addChild(pedalR)

        root.addChild(cranks)

        // Handlebar
        let handlebar = Entity()
        handlebar.name = "handlebar"
        let barMesh = MeshResource.generateCylinder(height: 0.64, radius: 0.026)
        let bar = ModelEntity(mesh: barMesh, materials: [darkMat])
        bar.name = "crossbar"
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        handlebar.addChild(bar)
        for side: Float in [-1, 1] {
            let gripMesh = MeshResource.generateCylinder(height: 0.22, radius: 0.024)
            let grip = ModelEntity(mesh: gripMesh, materials: [darkMat])
            grip.position = SIMD3(side * 0.28, -0.02, 0.04)
            grip.orientation = simd_quatf(angle: -0.3, axis: SIMD3(1, 0, 0))
            grip.name = "grip-\(side > 0 ? "R" : "L")"
            handlebar.addChild(grip)
        }
        handlebar.position = SIMD3(0, wheelR + 0.8, 0.35)
        root.addChild(handlebar)

        // Rider group
        rider.name = "rider"
        rider.position = SIMD3(0, wheelR + 0.5, -0.35)
        root.addChild(rider)

        // Athlete body (seated, aero tuck)
        athlete.build(into: rider, seated: true, accent: accent, opacity: opacity)
        // Position pelvis on saddle relative to rider group
        athlete.pelvis.position = SIMD3(0, 0.30, -0.05)
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose, reduceMotion: Bool) {
        guard case .bike(let bikePose) = pose else { return }

        // Wheels roll
        for wheel in wheels {
            wheel.orientation = simd_quatf(
                angle: Float(bikePose.wheelAngle),
                axis: SIMD3(1, 0, 0)
            )
        }

        // Cranks turn
        cranks.orientation = simd_quatf(
            angle: Float(bikePose.crankAngle),
            axis: SIMD3(1, 0, 0)
        )

        // Rider sway
        rider.orientation = simd_quatf(
            angle: Float(bikePose.riderSway),
            axis: SIMD3(0, 0, 1)
        )

        // Apply athlete joint pose (includes aero tuck and leg pedaling)
        athlete.applyPose(bikePose.joints)

        // Feet stay on pedals: adjust ankle/foot orientation to match pedal angle
        let footRotL = Float(bikePose.crankAngle)
        let footRotR = Float(bikePose.crankAngle + Double.pi)
        athlete.footL.orientation = simd_quatf(
            angle: footRotL,
            axis: SIMD3(1, 0, 0)
        )
        athlete.footR.orientation = simd_quatf(
            angle: footRotR,
            axis: SIMD3(1, 0, 0)
        )

        lastPose = bikePose
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
