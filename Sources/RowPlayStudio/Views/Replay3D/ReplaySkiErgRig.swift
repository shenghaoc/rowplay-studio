import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// SkiErg articulated rig: frame, cable, handles, poles, platform, and athlete body.
///
/// Contact invariants:
/// - Hands remain attached to handles
/// - Cable/pole endpoints follow the handles
/// - Feet remain on the platform
@MainActor
final class ReplaySkiErgRig: ReplaySportRig {
    let root = Entity()

    // Machine parts
    private let cable = Entity()
    private let leftHandle = Entity()
    private let rightHandle = Entity()
    private let footAnchorL = Entity()
    private let footAnchorR = Entity()
    private var poles: [Entity] = []

    // Athlete — either the lightweight procedural body or the V4 USDZ instance.
    private let athlete = ReplayAthleteRig()
    private var canonicalAthlete: ReplayAthleteInstance?
    private var poseAdapter: ReplayAthletePoseAdapter?
    private var canonicalRuntimeFailure = false

    // MARK: - Build

    func build(
        into parent: ModelEntity,
        accent: Color,
        opacity: Float,
        visualProvider: (any ReplayRigVisualProvider)? = nil,
        canonicalAthlete: ReplayAthleteInstance? = nil
    ) {
        root.name = "skierg-rig"
        parent.addChild(root)

        let postMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.32, alpha: 1),
            opacity: opacity
        )
        let handleMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
            opacity: opacity
        )
        let cableMat = ReplayMeshFactory.metalMaterial(
            NSColor.gray,
            opacity: opacity
        )
        let poleMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.94, alpha: 1),
            opacity: opacity
        )
        let accentMat = ReplayMeshFactory.accentMaterial(accent, opacity: opacity)

        // Frame posts
        let postMesh = MeshResource.generateBox(size: SIMD3(0.08, 1.8, 0.08))
        for x: Float in [-0.3, 0.3] {
            let post = Entity()
            post.name = "post-\(x > 0 ? "R" : "L")"
            let visualName = x > 0 ? "visual-post-R" : "visual-post-L"
            if visualProvider?.attachVisual(named: visualName, to: post) != true {
                let postModel = ModelEntity(mesh: postMesh, materials: [postMat])
                postModel.name = "post-model-\(x > 0 ? "R" : "L")"
                post.addChild(postModel)
            }
            post.position = SIMD3(x, 0.9, -0.5)
            root.addChild(post)
        }

        // Top bar
        let topBar = Entity()
        topBar.name = "topBar"
        if visualProvider?.attachVisual(named: "visual-topBar", to: topBar) != true {
            let topBarMesh = MeshResource.generateBox(size: SIMD3(0.7, 0.06, 0.06))
            let topBarModel = ModelEntity(mesh: topBarMesh, materials: [postMat])
            topBarModel.name = "topBar-model"
            topBar.addChild(topBarModel)
        }
        topBar.position = SIMD3(0, 1.8, -0.5)
        root.addChild(topBar)

        // Cable/pulley
        cable.name = "cable"
        if visualProvider?.attachVisual(named: "visual-cable", to: cable) != true {
            let cableMesh = MeshResource.generateCylinder(height: 1.2, radius: 0.01)
            let cableModel = ModelEntity(mesh: cableMesh, materials: [cableMat])
            cableModel.name = "cable-model"
            cable.addChild(cableModel)
        }
        cable.position = SIMD3(0, 1.2, -0.5)
        root.addChild(cable)

        // Handles
        let handleMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 0.25))

        leftHandle.name = "handle-L"
        if visualProvider?.attachVisual(named: "visual-handle-L", to: leftHandle) != true {
            let leftModel = ModelEntity(mesh: handleMesh, materials: [handleMat])
            leftModel.name = "handle-model-L"
            leftHandle.addChild(leftModel)
        }
        leftHandle.position = SIMD3(-0.15, 0.8, 0.1)
        root.addChild(leftHandle)

        rightHandle.name = "handle-R"
        if visualProvider?.attachVisual(named: "visual-handle-R", to: rightHandle) != true {
            let rightModel = ModelEntity(mesh: handleMesh, materials: [handleMat])
            rightModel.name = "handle-model-R"
            rightHandle.addChild(rightModel)
        }
        rightHandle.position = SIMD3(0.15, 0.8, 0.1)
        root.addChild(rightHandle)

        // Platform
        let platform = Entity()
        platform.name = "platform"
        if visualProvider?.attachVisual(named: "visual-platform", to: platform) != true {
            let platformMesh = MeshResource.generateBox(size: SIMD3(0.8, 0.06, 0.6))
            let platformModel = ModelEntity(mesh: platformMesh, materials: [accentMat])
            platformModel.name = "platform-model"
            platform.addChild(platformModel)
        }
        platform.position = SIMD3(0, 0.03, 0)
        footAnchorL.name = "foot-anchor-L"
        footAnchorL.position = SIMD3(-0.12, 0.03, 0)
        platform.addChild(footAnchorL)
        footAnchorR.name = "foot-anchor-R"
        footAnchorR.position = SIMD3(0.12, 0.03, 0)
        platform.addChild(footAnchorR)
        root.addChild(platform)

        // Poles
        for side: Float in [-1, 1] {
            let pole = Entity()
            pole.name = "pole-\(side > 0 ? "R" : "L")"
            let visualName = side > 0 ? "visual-pole-R" : "visual-pole-L"
            if visualProvider?.attachVisual(named: visualName, to: pole) != true {
                // Shaft
                let shaftMesh = MeshResource.generateCylinder(height: 1.2, radius: 0.015)
                let shaft = ModelEntity(mesh: shaftMesh, materials: [poleMat])
                shaft.position = SIMD3(0, -0.6, 0)
                shaft.name = "shaft"
                pole.addChild(shaft)

                // Grip
                let gripMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 0.16))
                let gripMat = ReplayMeshFactory.metalMaterial(
                    NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
                    opacity: opacity
                )
                let grip = ModelEntity(mesh: gripMesh, materials: [gripMat])
                grip.name = "grip"
                pole.addChild(grip)

                // Basket
                let basketMesh = MeshResource.generateCylinder(height: 0.03, radius: 0.06)
                let basket = ModelEntity(mesh: basketMesh, materials: [accentMat])
                basket.position = SIMD3(0, -1.15, 0)
                basket.name = "basket"
                pole.addChild(basket)
            }

            pole.position = SIMD3(side * 0.15, 0.8, 0.1)
            root.addChild(pole)
            poles.append(pole)
        }

        // Athlete body (standing). Canonical V4 and procedural paths are exclusive.
        if let canonicalAthlete {
            self.canonicalAthlete = canonicalAthlete
            self.poseAdapter = ReplayAthletePoseAdapter(contract: canonicalAthlete.contract)
            canonicalAthlete.attach(to: root)
            canonicalAthlete.root.scale = SIMD3(repeating: 0.95)
            canonicalAthlete.root.position = SIMD3(0, 0.72, 0.02)
            canonicalAthlete.captureBaseRootTransform()
        } else {
            athlete.build(
                into: root,
                seated: false,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = SIMD3(0, 0.72, 0.02)
        }
    }

    // MARK: - Pose Application

    func applyPose(_ pose: ReplaySportRigPose, motion: ReplayAthleteMotionSample?) {
        guard case .skierg(let skiPose) = pose else {
            assertionFailure("ReplaySkiErgRig.applyPose received non-skierg pose")
            return
        }

        // Finite guard at Studio/RealityKit boundary
        let handleY = ReplaySportRigFiniteGuard.finite(Float(skiPose.handleY), fallback: 0.42)
        let handleZ = ReplaySportRigFiniteGuard.finite(Float(skiPose.handleZ), fallback: 0.16)
        let poleRotation = ReplaySportRigFiniteGuard.finite(Float(skiPose.poleRotation), fallback: -0.1)
        let hipCompression = ReplaySportRigFiniteGuard.finite(Float(skiPose.hipCompression), fallback: 0)

        // Handles move with pull
        leftHandle.position = SIMD3(-0.15, handleY, handleZ)
        rightHandle.position = SIMD3(0.15, handleY, handleZ)

        // Poles swing with handles
        for pole in poles {
            pole.position.y = handleY
            pole.position.z = handleZ
            pole.orientation = simd_quatf(angle: poleRotation, axis: SIMD3(1, 0, 0))
        }

        // Cable spans from the top pulley to the moving handle midpoint.
        let cableTop = SIMD3<Float>(0, 1.8, -0.5)
        let cableBottom = SIMD3<Float>(0, handleY, handleZ)
        let cableDelta = cableBottom - cableTop
        cable.position = (cableTop + cableBottom) / 2
        cable.scale.y = max(0.001, simd_length(cableDelta) / 1.2)
        cable.orientation = simd_quatf(
            angle: atan2(cableDelta.z, cableDelta.y),
            axis: SIMD3(1, 0, 0)
        )

        let compressionOffset = hipCompression * 0.15
        let pelvisTarget = SIMD3<Float>(0, 0.72 - compressionOffset, 0.02)
        let handL = leftHandle.position(relativeTo: root)
        let handR = rightHandle.position(relativeTo: root)
        let footL = footAnchorL.position(relativeTo: root)
        let footR = footAnchorR.position(relativeTo: root)

        if let canonicalAthlete, let poseAdapter, let motion {
            poseAdapter.apply(sample: motion, sport: .skierg, to: canonicalAthlete)
            let targets = ReplayAthleteContactTargets(
                pelvis: pelvisTarget,
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
        } else {
            athlete.pelvis.position = pelvisTarget
            athlete.applyPose(skiPose.joints)
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
