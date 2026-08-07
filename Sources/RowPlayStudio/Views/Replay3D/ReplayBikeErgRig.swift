import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Road-bike replay rig driven by the portable bike fit contract.
///
/// Contact invariants:
/// - Tyre outer radii rest on the ground and roll without slip
/// - Hands remain on the contract-defined brake hoods
/// - Pelvis remains at the derived rider root above the analytic saddle
/// - Feet remain on opposite contract-radius pedals
@MainActor
final class ReplayBikeErgRig: ReplaySportRig {
    let root = Entity()

    private var wheels: [Entity] = []
    private let frame = Entity()
    private let cranks = Entity()
    private let saddle = Entity()
    private let handlebar = Entity()
    private let handleGripL = Entity()
    private let handleGripR = Entity()
    private let pedalL = Entity()
    private let pedalR = Entity()
    private let rider = Entity()

    // Fixed once during build; pose application never crosses source paths.
    private var source: ReplayRigSource?
    private var canonicalRuntimeFailure = false

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
        let tyreMat = ReplayMeshFactory.metalMaterial(
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1),
            opacity: opacity
        )
        let metalMat = ReplayMeshFactory.metalMaterial(NSColor.gray, opacity: opacity)
        let darkMat = ReplayMeshFactory.kitDarkMaterial(opacity: opacity)
        let outerWheelRadius = Float(ReplayBikeGripContract.axleY)

        for (name, z) in [
            ("front", Float(ReplayBikeGripContract.frontAxleZ)),
            ("rear", Float(ReplayBikeGripContract.rearAxleZ)),
        ] {
            let wheel = Entity()
            wheel.name = "wheel-\(name)"
            let visualName = name == "front" ? "visual-wheel-front" : "visual-wheel-rear"
            if visualProvider?.attachFittedVisual(
                named: visualName,
                to: wheel,
                targetSize: SIMD3(0.12, outerWheelRadius * 2, outerWheelRadius * 2)
            ) != true {
                wheel.addChild(ReplayMeshFactory.wheelEntity(
                    radius: outerWheelRadius,
                    tyreMaterial: tyreMat,
                    spokeMaterial: accentMat
                ))
            }
            wheel.position = SIMD3(0, outerWheelRadius, z)
            root.addChild(wheel)
            wheels.append(wheel)
        }

        frame.name = "frame"
        if visualProvider?.attachVisual(named: "visual-frame", to: frame) != true {
            buildProceduralFrame(
                into: frame,
                frameMaterial: accentMat,
                saddleMaterial: darkMat,
                cockpitMaterial: darkMat
            )
        }
        root.addChild(frame)

        saddle.name = "saddle"
        saddle.position = float3(
            x: 0,
            y: ReplayBikeGripContract.saddleY,
            z: ReplayBikeGripContract.saddleZ
        )
        root.addChild(saddle)

        cranks.name = "cranks"
        cranks.position = float3(
            x: 0,
            y: ReplayBikeGripContract.bbY,
            z: ReplayBikeGripContract.bbZ
        )
        if visualProvider?.attachVisual(named: "visual-drivetrain", to: cranks) != true {
            buildProceduralDrivetrain(
                into: cranks,
                metalMaterial: metalMat,
                pedalMaterial: darkMat
            )
        }

        pedalL.name = "pedal-L"
        pedalL.position = SIMD3(
            -Float(ReplayBikeGripContract.crankLateral),
            Float(ReplayBikeGripContract.crankRadius),
            0
        )
        cranks.addChild(pedalL)
        pedalR.name = "pedal-R"
        pedalR.position = SIMD3(
            Float(ReplayBikeGripContract.crankLateral),
            -Float(ReplayBikeGripContract.crankRadius),
            0
        )
        cranks.addChild(pedalR)
        root.addChild(cranks)

        handlebar.name = "handlebar"
        handlebar.position = float3(ReplayBikeGripContract.handlebarBase)
        let gripLocalY = Float(
            ReplayBikeGripContract.handlebarGripY - ReplayBikeGripContract.handlebarBase.y
        )
        let gripLocalZ = Float(
            ReplayBikeGripContract.handlebarGripZ - ReplayBikeGripContract.handlebarBase.z
        )
        handleGripL.name = "handle-grip-anchor-L"
        handleGripL.position = SIMD3(
            -Float(ReplayBikeGripContract.handlebarGripHalfSpan),
            gripLocalY,
            gripLocalZ
        )
        handlebar.addChild(handleGripL)
        handleGripR.name = "handle-grip-anchor-R"
        handleGripR.position = SIMD3(
            Float(ReplayBikeGripContract.handlebarGripHalfSpan),
            gripLocalY,
            gripLocalZ
        )
        handlebar.addChild(handleGripR)
        root.addChild(handlebar)

        rider.name = "rider"
        rider.position = float3(ReplayBikeGripContract.riderRoot)
        root.addChild(rider)

        // Athlete body (seated, aero tuck). Canonical V4 and procedural are exclusive.
        if let canonicalAthlete {
            source = .bundled(ReplayBundledAthleteRuntime(
                instance: canonicalAthlete,
                sport: .bike,
                parent: rider,
                rootScale: 1.0,
                rootPosition: .zero
            ))
        } else {
            let athlete = ReplayAthleteRig()
            athlete.build(
                into: rider,
                seated: true,
                accent: accent,
                opacity: opacity,
                visualProvider: nil
            )
            athlete.pelvis.position = float3(ReplayBikeGripContract.riderPelvisOffset)
            source = .procedural(athlete)
        }
    }

    private func buildProceduralFrame(
        into parent: Entity,
        frameMaterial: any RealityKit.Material,
        saddleMaterial: any RealityKit.Material,
        cockpitMaterial: any RealityKit.Material
    ) {
        let bb = float3(x: 0, y: ReplayBikeGripContract.bbY, z: ReplayBikeGripContract.bbZ)
        let seatCluster = float3(
            x: 0,
            y: ReplayBikeGripContract.seatClusterY,
            z: ReplayBikeGripContract.seatClusterZ
        )
        let headBottom = float3(
            x: 0,
            y: ReplayBikeGripContract.headBottomY,
            z: ReplayBikeGripContract.headBottomZ
        )
        let headTop = float3(
            x: 0,
            y: ReplayBikeGripContract.headTopY,
            z: ReplayBikeGripContract.headTopZ
        )

        parent.addChild(tube(
            name: "downTube", from: bb, to: headBottom, radius: 0.0185,
            material: frameMaterial
        ))
        parent.addChild(tube(
            name: "seatTube", from: bb, to: seatCluster, radius: 0.0165,
            material: frameMaterial
        ))
        parent.addChild(tube(
            name: "topTube", from: seatCluster, to: headTop, radius: 0.015,
            material: frameMaterial
        ))
        parent.addChild(tube(
            name: "headTube", from: headBottom, to: headTop, radius: 0.021,
            material: frameMaterial
        ))

        for side: Float in [-1, 1] {
            let rearAxle = SIMD3(
                side * 0.055,
                Float(ReplayBikeGripContract.axleY),
                Float(ReplayBikeGripContract.rearAxleZ)
            )
            let frontAxle = SIMD3(
                side * 0.048,
                Float(ReplayBikeGripContract.axleY),
                Float(ReplayBikeGripContract.frontAxleZ)
            )
            let bbSide = SIMD3(side * 0.036, bb.y, bb.z)
            let seatSide = SIMD3(side * 0.026, seatCluster.y, seatCluster.z)
            let crown = SIMD3(side * 0.022, headBottom.y - 0.012, headBottom.z + 0.004)
            parent.addChild(tube(
                name: "chainStay-\(side > 0 ? "R" : "L")",
                from: rearAxle,
                to: bbSide,
                radius: 0.0115,
                material: frameMaterial
            ))
            parent.addChild(tube(
                name: "seatStay-\(side > 0 ? "R" : "L")",
                from: rearAxle,
                to: seatSide,
                radius: 0.0095,
                material: frameMaterial
            ))
            parent.addChild(tube(
                name: "forkBlade-\(side > 0 ? "R" : "L")",
                from: crown,
                to: frontAxle,
                radius: 0.0115,
                material: frameMaterial
            ))
        }

        let clamp = float3(
            x: 0,
            y: ReplayBikeGripContract.saddleClampY,
            z: ReplayBikeGripContract.saddleZ + ReplayBikeGripContract.saddleClampZ
        )
        parent.addChild(tube(
            name: "seatPost", from: seatCluster, to: clamp, radius: 0.0135,
            material: frameMaterial
        ))
        parent.addChild(tube(
            name: "stem", from: headTop, to: float3(ReplayBikeGripContract.handlebarBase),
            radius: 0.0125,
            material: frameMaterial
        ))

        buildAnalyticSaddle(into: parent, material: saddleMaterial)

        let bar = ModelEntity(
            mesh: .generateCylinder(
                height: Float(ReplayBikeGripContract.handlebarGripHalfSpan * 2),
                radius: 0.0125
            ),
            materials: [cockpitMaterial]
        )
        bar.name = "handlebar-crossbar"
        bar.position = float3(ReplayBikeGripContract.handlebarBase)
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        parent.addChild(bar)
        for side: Float in [-1, 1] {
            let hood = ModelEntity(
                mesh: .generateCylinder(height: 0.11, radius: Float(ReplayBikeGripContract.hoodRadius)),
                materials: [cockpitMaterial]
            )
            hood.name = "brake-hood-\(side > 0 ? "R" : "L")"
            hood.position = SIMD3(
                side * Float(ReplayBikeGripContract.handlebarGripHalfSpan),
                Float(ReplayBikeGripContract.handlebarGripY),
                Float(ReplayBikeGripContract.handlebarGripZ)
            )
            hood.orientation = simd_quatf(
                angle: Float(ReplayBikeGripContract.hoodRotationX),
                axis: SIMD3(1, 0, 0)
            )
            parent.addChild(hood)
        }
    }

    private func buildAnalyticSaddle(
        into parent: Entity,
        material: any RealityKit.Material
    ) {
        let saddleRoot = Entity()
        saddleRoot.name = "analytic-saddle"
        saddleRoot.position = float3(
            x: 0,
            y: ReplayBikeGripContract.saddleY,
            z: ReplayBikeGripContract.saddleZ
        )
        let stations = ReplayBikeSaddle.stations
        for index in 1..<stations.count {
            let first = stations[index - 1]
            let second = stations[index]
            let halfWidth = Float((first.halfWidth + second.halfWidth) / 2)
            let cutout = Float((first.cutout + second.cutout) / 2)
            let segmentWidth = max(0.001, halfWidth - cutout)
            let segmentLength = Float(second.z - first.z)
            let topDrop = Float(
                (first.dropOuter + first.dropChannel
                    + second.dropOuter + second.dropChannel) / 4
            )
            let topY = Float(ReplayBikeGripContract.saddlePadHalfHeight) - topDrop
            for side: Float in [-1, 1] {
                let segment = ModelEntity(
                    mesh: .generateBox(size: SIMD3(
                        segmentWidth,
                        Float(ReplayBikeSaddle.shellThickness),
                        segmentLength
                    )),
                    materials: [material]
                )
                segment.name = "saddle-wing-\(side > 0 ? "R" : "L")-\(index)"
                segment.position = SIMD3(
                    side * (cutout + segmentWidth / 2),
                    topY - Float(ReplayBikeSaddle.shellThickness) / 2,
                    Float((first.z + second.z) / 2)
                )
                saddleRoot.addChild(segment)
            }
        }
        parent.addChild(saddleRoot)
    }

    private func buildProceduralDrivetrain(
        into parent: Entity,
        metalMaterial: any RealityKit.Material,
        pedalMaterial: any RealityKit.Material
    ) {
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.012, radius: 0.104),
            materials: [metalMaterial]
        )
        ring.name = "chainRing"
        ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        parent.addChild(ring)

        for side: Float in [-1, 1] {
            let arm = ModelEntity(
                mesh: .generateBox(size: SIMD3(
                    0.018,
                    Float(ReplayBikeGripContract.crankRadius),
                    0.03
                )),
                materials: [metalMaterial]
            )
            arm.name = "crank-arm-\(side > 0 ? "R" : "L")"
            arm.position = SIMD3(
                side * 0.038,
                side * Float(ReplayBikeGripContract.crankRadius) / 2,
                0
            )
            parent.addChild(arm)

            let pedal = ModelEntity(
                mesh: .generateBox(size: SIMD3(0.075, 0.014, 0.062)),
                materials: [pedalMaterial]
            )
            pedal.name = "pedal-model-\(side > 0 ? "R" : "L")"
            pedal.position = SIMD3(
                side * Float(ReplayBikeGripContract.crankLateral),
                side * Float(ReplayBikeGripContract.crankRadius),
                0
            )
            parent.addChild(pedal)
        }
    }

    private func tube(
        name: String,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: any RealityKit.Material
    ) -> ModelEntity {
        let delta = end - start
        let length = max(0.001, simd_length(delta))
        let model = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [material]
        )
        model.name = name
        model.position = (start + end) / 2
        model.orientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: delta / length
        )
        return model
    }

    private func float3(
        x: Double,
        y: Double,
        z: Double
    ) -> SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }

    private func float3(_ value: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(value.x), Float(value.y), Float(value.z))
    }

    // MARK: - Pose Application

    @discardableResult
    func applyPose(
        _ pose: ReplaySportRigPose,
        motion: ReplayAthleteMotionSample?
    ) -> ReplaySportRigPoseResult {
        guard case .bike(let bikePose) = pose else {
            assertionFailure("ReplayBikeErgRig.applyPose received non-bike pose")
            return .failed(.unexpectedSport)
        }

        let wheelAngle = ReplaySportRigFiniteGuard.finite(Float(bikePose.wheelAngle), fallback: 0)
        let crankAngle = ReplaySportRigFiniteGuard.finite(Float(bikePose.crankAngle), fallback: 0)
        let riderSway = ReplaySportRigFiniteGuard.finite(Float(bikePose.riderSway), fallback: 0)

        for wheel in wheels {
            wheel.orientation = simd_quatf(angle: wheelAngle, axis: SIMD3(1, 0, 0))
        }
        cranks.orientation = simd_quatf(angle: crankAngle, axis: SIMD3(1, 0, 0))
        rider.orientation = simd_quatf(angle: riderSway, axis: SIMD3(0, 0, 1))

        let pelvisTarget = rider.position(relativeTo: root)
        let handL = handleGripL.position(relativeTo: root)
        let handR = handleGripR.position(relativeTo: root)
        let footL = pedalL.position(relativeTo: root)
        let footR = pedalR.position(relativeTo: root)
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
            athlete.applyPose(bikePose.joints)
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
