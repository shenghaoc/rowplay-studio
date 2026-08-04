import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// SkiErg articulated rig: classic roller skis, independent rigid poles, and
/// a standing athlete. The legacy indoor tower/cable/platform representation
/// is intentionally absent.
///
/// Contact invariants:
/// - Hands remain on the pole grips
/// - Every hand-to-basket segment is exactly the contract pole length
/// - Loaded baskets use the deterministic course plant carried by the pose
/// - Feet remain on the ski bindings
@MainActor
final class ReplaySkiErgRig: ReplaySportRig {
    let root = Entity()

    private struct Pole {
        let side: Float
        let root: Entity
        let gripAnchor: Entity
        let basketAnchor: Entity
    }

    private let footAnchorL = Entity()
    private let footAnchorR = Entity()
    private var poles: [Pole] = []

    // Fixed once during build; pose application never crosses source paths.
    private var source: ReplayRigSource?
    private var canonicalRuntimeFailure = false

    private let poleLength = Float(ReplaySkiGripContract.athleteProportions.poleLength)
    private let contactY: Float = 0.055

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

        let equipment = ReplaySkiGripContract.athleteProportions
        let accentMat = ReplayMeshFactory.accentMaterial(accent, opacity: opacity)
        let darkMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.16, alpha: 1),
            opacity: opacity
        )
        let poleMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.94, alpha: 1),
            opacity: opacity
        )

        for side: Float in [-1, 1] {
            let suffix = side > 0 ? "R" : "L"
            let ski = Entity()
            ski.name = "ski-\(suffix)"
            let visualName = side > 0 ? "visual-ski-R" : "visual-ski-L"
            if visualProvider?.attachVisual(named: visualName, to: ski) != true {
                buildProceduralSki(
                    into: ski,
                    width: Float(equipment.skiWidth),
                    length: Float(equipment.skiLength),
                    accentMaterial: accentMat,
                    darkMaterial: darkMat
                )
            }
            ski.position = SIMD3(side * Float(equipment.skiCenterOffset), 0, 0.16)
            root.addChild(ski)
        }

        footAnchorL.name = "foot-anchor-L"
        footAnchorL.position = SIMD3(-Float(equipment.skiCenterOffset), 0.055, 0.18)
        root.addChild(footAnchorL)
        footAnchorR.name = "foot-anchor-R"
        footAnchorR.position = SIMD3(Float(equipment.skiCenterOffset), 0.055, 0.18)
        root.addChild(footAnchorR)

        for side: Float in [-1, 1] {
            poles.append(buildPole(
                side: side,
                accentMaterial: accentMat,
                darkMaterial: darkMat,
                poleMaterial: poleMat,
                visualProvider: visualProvider
            ))
        }

        // Athlete body (standing). Canonical V4 and procedural paths are exclusive.
        if let canonicalAthlete {
            source = .bundled(ReplayBundledAthleteRuntime(
                instance: canonicalAthlete,
                sport: .skierg,
                parent: root,
                rootScale: 0.95,
                rootPosition: SIMD3(0, 0.72, 0.02)
            ))
        } else {
            let athlete = ReplayAthleteRig()
            athlete.build(
                into: root,
                seated: false,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = SIMD3(0, 0.72, 0.02)
            source = .procedural(athlete)
        }
    }

    private func buildProceduralSki(
        into parent: Entity,
        width: Float,
        length: Float,
        accentMaterial: any RealityKit.Material,
        darkMaterial: any RealityKit.Material
    ) {
        let base = ModelEntity(
            mesh: .generateBox(size: SIMD3(width, 0.022, length)),
            materials: [darkMaterial]
        )
        base.name = "ski-base"
        base.position.y = 0.011
        parent.addChild(base)

        let topSheet = ModelEntity(
            mesh: .generateBox(size: SIMD3(width * 0.82, 0.006, length * 0.90)),
            materials: [accentMaterial]
        )
        topSheet.name = "ski-top-sheet"
        topSheet.position.y = 0.025
        parent.addChild(topSheet)

        let bindingPlate = ModelEntity(
            mesh: .generateBox(size: SIMD3(width * 0.88, 0.012, 0.24)),
            materials: [darkMaterial]
        )
        bindingPlate.name = "binding-plate"
        bindingPlate.position = SIMD3(0, 0.036, 0.02)
        parent.addChild(bindingPlate)

        let bindingToe = ModelEntity(
            mesh: .generateBox(size: SIMD3(width * 0.81, 0.022, 0.045)),
            materials: [accentMaterial]
        )
        bindingToe.name = "binding-toe"
        bindingToe.position = SIMD3(0, 0.052, -0.08)
        parent.addChild(bindingToe)

        let bindingHeel = ModelEntity(
            mesh: .generateBox(size: SIMD3(width * 0.66, 0.012, 0.055)),
            materials: [darkMaterial]
        )
        bindingHeel.name = "binding-heel"
        bindingHeel.position = SIMD3(0, 0.046, 0.10)
        parent.addChild(bindingHeel)
    }

    private func buildPole(
        side: Float,
        accentMaterial: any RealityKit.Material,
        darkMaterial: any RealityKit.Material,
        poleMaterial: any RealityKit.Material,
        visualProvider: (any ReplayRigVisualProvider)?
    ) -> Pole {
        let suffix = side > 0 ? "R" : "L"
        let pole = Entity()
        pole.name = "pole-\(suffix)"

        let shaftVisualName = "visual-pole-shaft-\(suffix)"
        if visualProvider?.attachFittedVisual(
            named: shaftVisualName,
            to: pole,
            targetSize: SIMD3(0.018, poleLength, 0.018),
            targetCenter: SIMD3(0, -poleLength / 2, 0)
        ) != true {
            let shaft = ModelEntity(
                mesh: .generateCylinder(height: poleLength, radius: 0.009),
                materials: [poleMaterial]
            )
            shaft.name = "pole-shaft-\(suffix)"
            shaft.position.y = -poleLength / 2
            pole.addChild(shaft)
        }

        let gripLength: Float = 0.15
        let gripRadius = Float(ReplaySkiGripContract.poleGripRadius)
        let gripVisualName = "visual-pole-grip-\(suffix)"
        if visualProvider?.attachFittedVisual(
            named: gripVisualName,
            to: pole,
            targetSize: SIMD3(gripRadius * 2, gripLength, gripRadius * 2),
            targetCenter: SIMD3(0, -gripLength / 2, 0)
        ) != true {
            let grip = ModelEntity(
                mesh: .generateCylinder(height: gripLength, radius: gripRadius),
                materials: [darkMaterial]
            )
            grip.name = "pole-grip-\(suffix)"
            grip.position.y = -gripLength / 2
            pole.addChild(grip)
        }

        let basketVisualName = "visual-pole-basket-\(suffix)"
        if visualProvider?.attachFittedVisual(
            named: basketVisualName,
            to: pole,
            targetSize: SIMD3(0.056, 0.014, 0.056),
            targetCenter: SIMD3(0, -poleLength, 0)
        ) != true {
            let basket = ModelEntity(
                mesh: .generateCylinder(height: 0.014, radius: 0.028),
                materials: [accentMaterial]
            )
            basket.name = "pole-basket-\(suffix)"
            basket.position.y = -poleLength
            pole.addChild(basket)
        }

        let gripAnchor = Entity()
        gripAnchor.name = "pole-grip-anchor-\(suffix)"
        pole.addChild(gripAnchor)

        let basketAnchor = Entity()
        basketAnchor.name = "pole-basket-anchor-\(suffix)"
        basketAnchor.position.y = -poleLength
        pole.addChild(basketAnchor)

        root.addChild(pole)
        return Pole(side: side, root: pole, gripAnchor: gripAnchor, basketAnchor: basketAnchor)
    }

    // MARK: - Pose Application

    @discardableResult
    func applyPose(
        _ pose: ReplaySportRigPose,
        motion: ReplayAthleteMotionSample?
    ) -> ReplaySportRigPoseResult {
        guard case .skierg(let skiPose) = pose else {
            assertionFailure("ReplaySkiErgRig.applyPose received non-skierg pose")
            return .failed(.unexpectedSport)
        }

        let handleY = ReplaySportRigFiniteGuard.finite(Float(skiPose.handleY), fallback: 1.2)
        let handleZ = ReplaySportRigFiniteGuard.finite(Float(skiPose.handleZ), fallback: 0.2)
        let poleRotation = ReplaySportRigFiniteGuard.finite(Float(skiPose.poleRotation), fallback: -0.2)
        let poleContact = min(
            1,
            max(0, ReplaySportRigFiniteGuard.finite(Float(skiPose.poleContact), fallback: 0))
        )
        let plantBasketZ = ReplaySportRigFiniteGuard.finite(
            Float(skiPose.plantBasketZ),
            fallback: Float(ReplaySkiGripContract.athleteProportions.polePlantForwardOffset)
        )
        let hipCompression = ReplaySportRigFiniteGuard.finite(
            Float(skiPose.hipCompression),
            fallback: 0
        )

        let equipment = ReplaySkiGripContract.athleteProportions
        var handTargets: [SIMD3<Float>] = []
        for pole in poles {
            let desiredHand = SIMD3<Float>(
                pole.side * Float(equipment.skiCenterOffset),
                0.82 - (1.58 - handleY) * (0.42 / 1.02),
                0.28 - (0.66 - handleZ) * (0.38 / 0.94)
            )

            // Free-flight baskets swing behind the carried hand at an exact
            // pole length. The contact channel rotates that direction toward
            // the deterministic course-space plant; normalizing the blended
            // direction preserves rigidity throughout both hand-offs.
            let carriedDirection = normalizedOrFallback(
                SIMD3(
                    pole.side * 0.12,
                    -max(0.18, cos(poleRotation)),
                    sin(poleRotation)
                ),
                fallback: SIMD3(0, -1, 0)
            )
            let freeBasket = desiredHand + carriedDirection * poleLength
            let plantBasket = SIMD3<Float>(
                pole.side * Float(equipment.polePlantLateralOffset),
                contactY,
                plantBasketZ
            )
            let blendedBasket = freeBasket + (plantBasket - freeBasket) * poleContact
            let handDirection = normalizedOrFallback(
                desiredHand - blendedBasket,
                fallback: SIMD3(0, 1, 0)
            )
            let solvedHand = blendedBasket + handDirection * poleLength

            pole.root.position = solvedHand
            pole.root.orientation = simd_quatf(
                from: SIMD3<Float>(0, -1, 0),
                to: normalizedOrFallback(blendedBasket - solvedHand, fallback: SIMD3(0, -1, 0))
            )
            handTargets.append(pole.gripAnchor.position(relativeTo: root))
        }

        let compressionOffset = hipCompression * 0.15
        let pelvisTarget = SIMD3<Float>(0, 0.72 - compressionOffset, 0.02)
        let footL = footAnchorL.position(relativeTo: root)
        let footR = footAnchorR.position(relativeTo: root)
        let targets = ReplayAthleteContactTargets(
            pelvis: pelvisTarget,
            leftHand: handTargets[0],
            rightHand: handTargets[1],
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
            athlete.applyPose(skiPose.joints)
            athlete.handL.setPosition(handTargets[0], relativeTo: root)
            athlete.handR.setPosition(handTargets[1], relativeTo: root)
            athlete.footL.setPosition(footL, relativeTo: root)
            athlete.footR.setPosition(footR, relativeTo: root)
            return .applied
        case nil:
            return .failed(.motionSampleRejected)
        }
    }

    private func normalizedOrFallback(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let length = simd_length(value)
        guard length.isFinite, length > 1e-6 else { return fallback }
        return value / length
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
