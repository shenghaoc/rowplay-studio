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
    private let handleGripL = Entity()
    private let handleGripR = Entity()

    // Rider group (contains athlete body)
    private let rider = Entity()

    // Athlete — either the lightweight procedural body or the V4 USDZ instance.
    private let athlete = ReplayAthleteRig()
    private var canonicalAthlete: ReplayAthleteInstance?
    private var poseAdapter: ReplayAthletePoseAdapter?
    private var canonicalRuntimeFailure = false

    // Pedal references for foot attachment
    private let pedalL = Entity()
    private let pedalR = Entity()

    // MARK: - Build

    func build(
        into parent: ModelEntity,
        accent: Color,
        opacity: Float,
        visualProvider: (any ReplayRigVisualProvider)? = nil,
        canonicalAthlete: ReplayAthleteInstance? = nil
    ) {
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

        // Wheels
        for z: Float in [0.85, -0.85] {
            let wheel = Entity()
            wheel.name = "wheel-\(z > 0 ? "front" : "rear")"
            let visualName = z > 0 ? "visual-wheel-front" : "visual-wheel-rear"
            if visualProvider?.attachVisual(named: visualName, to: wheel) != true {
                wheel.addChild(ReplayMeshFactory.wheelEntity(
                    radius: wheelR,
                    tyreMaterial: tyreMat,
                    spokeMaterial: spokeMat
                ))
            }
            wheel.position = SIMD3(0, wheelR, z)
            root.addChild(wheel)
            wheels.append(wheel)
        }

        // Frame: down tube, seat tube, top tube, chain stays
        let downTube = Entity()
        downTube.name = "downTube"
        if visualProvider?.attachVisual(named: "visual-downTube", to: downTube) != true {
            let downTubeMesh = MeshResource.generateBox(size: SIMD3(0.08, 0.08, 1.6))
            let downTubeModel = ModelEntity(mesh: downTubeMesh, materials: [frameMat])
            downTubeModel.name = "downTube-model"
            downTube.addChild(downTubeModel)
        }
        downTube.position = SIMD3(0, wheelR + 0.15, 0)
        root.addChild(downTube)

        let seatTube = Entity()
        seatTube.name = "seatTube"
        if visualProvider?.attachVisual(named: "visual-seatTube", to: seatTube) != true {
            let seatTubeMesh = MeshResource.generateBox(size: SIMD3(0.08, 0.7, 0.08))
            let seatTubeModel = ModelEntity(mesh: seatTubeMesh, materials: [frameMat])
            seatTubeModel.name = "seatTube-model"
            seatTube.addChild(seatTubeModel)
        }
        seatTube.position = SIMD3(0, wheelR + 0.45, -0.4)
        root.addChild(seatTube)

        let topTube = Entity()
        topTube.name = "topTube"
        if visualProvider?.attachVisual(named: "visual-topTube", to: topTube) != true {
            let topTubeMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 1.1))
            let topTubeModel = ModelEntity(mesh: topTubeMesh, materials: [frameMat])
            topTubeModel.name = "topTube-model"
            topTube.addChild(topTubeModel)
        }
        topTube.position = SIMD3(0, wheelR + 0.75, -0.15)
        root.addChild(topTube)

        // Procedural-only chain stays. The bundled bike frame already carries
        // its own geometry; adding procedural stays on Medium+ would produce a
        // hybrid frame instead of the complete bundled / complete procedural split.
        if visualProvider?.usesBundledAssets != true {
            for side: Float in [-1, 1] {
                let stayMesh = MeshResource.generateBox(size: SIMD3(0.03, 0.03, 0.85))
                let stay = ModelEntity(mesh: stayMesh, materials: [frameMat])
                stay.name = "chainStay-\(side > 0 ? "R" : "L")"
                stay.position = SIMD3(side * 0.06, wheelR + 0.05, 0.4)
                root.addChild(stay)
            }
        }

        // Saddle
        saddle.name = "saddle"
        if visualProvider?.attachVisual(named: "visual-saddle", to: saddle) != true {
            let saddleMesh = MeshResource.generateBox(size: SIMD3(0.18, 0.05, 0.30))
            let saddleMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)
            let saddleModel = ModelEntity(mesh: saddleMesh, materials: [saddleMat])
            saddleModel.name = "saddle-model"
            saddle.addChild(saddleModel)
        }
        saddle.position = SIMD3(0, wheelR + 0.8, -0.4)
        root.addChild(saddle)

        // Cranks with chain ring and pedals
        cranks.name = "cranks"
        cranks.position = SIMD3(0, wheelR, -0.05)
        // The bundled crank arms sit on the same rotating parent as the
        // existing chain ring and pedals; `applyPose` remains unchanged.
        _ = visualProvider?.attachVisual(named: "visual-cranks", to: cranks)

        // Chain ring
        let chainRing = Entity()
        chainRing.name = "chainRing"
        if visualProvider?.attachVisual(named: "visual-chainRing", to: chainRing) != true {
            let chainRingMesh = MeshResource.generateSphere(radius: 0.16)
            let chainRingModel = ModelEntity(mesh: chainRingMesh, materials: [metalMat])
            chainRingModel.name = "chainRing-model"
            chainRingModel.scale = SIMD3(1, 0.12, 1)
            chainRing.addChild(chainRingModel)
        }
        cranks.addChild(chainRing)

        // Pedals
        let pedalMesh = MeshResource.generateBox(size: SIMD3(0.22, 0.05, 0.10))
        let pedalMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)

        pedalL.name = "pedal-L"
        if visualProvider?.attachVisual(named: "visual-pedal-L", to: pedalL) != true {
            let pedalLModel = ModelEntity(mesh: pedalMesh, materials: [pedalMat])
            pedalLModel.name = "pedal-model-L"
            pedalL.addChild(pedalLModel)
        }
        pedalL.position = SIMD3(-0.1, 0.18, 0)
        cranks.addChild(pedalL)

        pedalR.name = "pedal-R"
        if visualProvider?.attachVisual(named: "visual-pedal-R", to: pedalR) != true {
            let pedalRModel = ModelEntity(mesh: pedalMesh, materials: [pedalMat])
            pedalRModel.name = "pedal-model-R"
            pedalR.addChild(pedalRModel)
        }
        pedalR.position = SIMD3(0.1, -0.18, 0)
        cranks.addChild(pedalR)

        root.addChild(cranks)

        // Handlebar
        let handlebar = Entity()
        handlebar.name = "handlebar"
        if visualProvider?.attachVisual(named: "visual-handlebar", to: handlebar) != true {
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
        }
        handlebar.position = SIMD3(0, wheelR + 0.8, 0.35)
        handleGripL.name = "handle-grip-anchor-L"
        handleGripL.position = SIMD3(-0.28, -0.02, 0.04)
        handlebar.addChild(handleGripL)
        handleGripR.name = "handle-grip-anchor-R"
        handleGripR.position = SIMD3(0.28, -0.02, 0.04)
        handlebar.addChild(handleGripR)
        root.addChild(handlebar)

        // Rider group
        rider.name = "rider"
        // Pivot sway at the saddle/pelvis contact so the rider cannot slide
        // laterally off the saddle.
        rider.position = saddle.position
        root.addChild(rider)

        // Athlete body (seated, aero tuck). Canonical V4 and procedural are exclusive.
        if let canonicalAthlete {
            self.canonicalAthlete = canonicalAthlete
            self.poseAdapter = ReplayAthletePoseAdapter(contract: canonicalAthlete.contract)
            canonicalAthlete.attach(to: rider)
            canonicalAthlete.root.scale = SIMD3(repeating: 0.95)
            canonicalAthlete.root.position = .zero
            canonicalAthlete.captureBaseRootTransform()
        } else {
            athlete.build(
                into: rider,
                seated: true,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = .zero
        }
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose, motion: ReplayAthleteMotionSample?) {
        guard case .bike(let bikePose) = pose else {
            assertionFailure("ReplayBikeErgRig.applyPose received non-bike pose")
            return
        }

        // Finite guard at Studio/RealityKit boundary
        let wheelAngle = ReplaySportRigFiniteGuard.finite(Float(bikePose.wheelAngle), fallback: 0)
        let crankAngle = ReplaySportRigFiniteGuard.finite(Float(bikePose.crankAngle), fallback: 0)
        let riderSway = ReplaySportRigFiniteGuard.finite(Float(bikePose.riderSway), fallback: 0)

        // Wheels roll
        for wheel in wheels {
            wheel.orientation = simd_quatf(angle: wheelAngle, axis: SIMD3(1, 0, 0))
        }

        // Cranks turn
        cranks.orientation = simd_quatf(angle: crankAngle, axis: SIMD3(1, 0, 0))

        // Rider sway
        rider.orientation = simd_quatf(angle: riderSway, axis: SIMD3(0, 0, 1))

        let pelvisTarget = SIMD3<Float>.zero
        let handL = handleGripL.position(relativeTo: root)
        let handR = handleGripR.position(relativeTo: root)
        let footL = pedalL.position(relativeTo: root)
        let footR = pedalR.position(relativeTo: root)

        if let canonicalAthlete, let poseAdapter, let motion {
            poseAdapter.apply(sample: motion, sport: .bike, to: canonicalAthlete)
            // Contact space is the rig root so pedals and grips stay authoritative.
            let targets = ReplayAthleteContactTargets(
                pelvis: rider.position(relativeTo: root),
                leftHand: handL,
                rightHand: handR,
                leftFoot: footL,
                rightFoot: footR
            )
            if canonicalAthlete.hasFiniteJointTransforms(), ReplayAthleteContactSolver.prepare(instance: canonicalAthlete) {
                ReplayAthleteContactSolver.orientHandsToTargets(
                    instance: canonicalAthlete,
                    targets: targets,
                    relativeTo: root
                )
                let contactError = ReplayAthleteContactSolver.constrain(
                    instance: canonicalAthlete,
                    targets: targets,
                    relativeTo: root
                )
                canonicalRuntimeFailure = !ReplayAthleteContactSolver.isUsable(contactError)
                    || !canonicalAthlete.hasFiniteJointTransforms()
            } else {
                canonicalRuntimeFailure = true
            }
            // Keep a local zero under the swaying rider group after world placement.
            _ = pelvisTarget
        } else {
            athlete.applyPose(bikePose.joints)
            athlete.handL.setPosition(handL, relativeTo: root)
            athlete.handR.setPosition(handR, relativeTo: root)
            athlete.footL.setPosition(footL, relativeTo: root)
            athlete.footR.setPosition(footR, relativeTo: root)
        }
    }

    func applyGhostTranslucency() {
        ReplaySportRigTranslucency.apply(
            to: root,
            opacity: 0.45,
            excluding: canonicalAthlete?.athleteEntity
        )
    }

    func consumeCanonicalRuntimeFailure() -> Bool {
        defer { canonicalRuntimeFailure = false }
        return canonicalRuntimeFailure
    }
}
