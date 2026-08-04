import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayBundledSportRigTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
        ReplayAssetLibrary.shared.resetCacheForTesting()
    }

    func testCompleteV4AndEquipmentContractsAcceptEveryBundledSportSet() async {
        for sport in ReplayAssetCatalog.supportedSports {
            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNotNil(assetSet, "Expected complete \(sport.rawValue) package")
            XCTAssertNotNil(
                assetSet?.makeAthleteInstance(
                    sport: sport,
                    name: "contract-probe",
                    isRival: false,
                    quality: .ultra
                )
            )
        }
    }

    func testCanonicalContactGateRejectsDetachedOrNonfiniteSkeletons() {
        let acceptable = ReplayAthleteContactError(
            leftHand: 0.009,
            rightHand: 0.008,
            leftFoot: 0.03,
            rightFoot: 0.04,
            pelvis: 0.05
        )
        XCTAssertTrue(ReplayAthleteContactSolver.isUsable(acceptable))

        let detached = ReplayAthleteContactError(
            leftHand: ReplayAthleteContactSolver.gripChannelContactBudgetMeters + 0.001,
            rightHand: 0,
            leftFoot: 0,
            rightFoot: 0,
            pelvis: 0
        )
        XCTAssertFalse(ReplayAthleteContactSolver.isUsable(detached))

        let nonfinite = ReplayAthleteContactError(
            leftHand: .infinity,
            rightHand: 0,
            leftFoot: 0,
            rightFoot: 0,
            pelvis: 0
        )
        XCTAssertFalse(ReplayAthleteContactSolver.isUsable(nonfinite))
    }

    func testSceneBuilderUsesOneCompleteProceduralSceneWhenBundleIsUnavailable() {
        for sport in ReplayAssetCatalog.supportedSports {
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.ultra.configuration,
                effectiveQuality: .ultra,
                bundledAssetSet: nil
            )

            XCTAssertEqual(scene.visualSource, .procedural)
            XCTAssertFalse(scene.usesCanonicalAthlete)
            XCTAssertNotNil(scene.liveRig.root.replayDescendant(named: "pelvis"))
            XCTAssertNotNil(scene.ghostRig.root.replayDescendant(named: "pelvis"))
            XCTAssertNil(scene.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName))
        }
    }

    func testWrongSportAndCloneFailureBothSelectCompleteProceduralScene() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let rowerSet = try XCTUnwrap(loaded)

        let wrongSport = Replay3DSceneBuilder.buildScene(
            sport: .bike,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.ultra.configuration,
            effectiveQuality: .ultra,
            bundledAssetSet: rowerSet
        )
        assertCompleteProceduralScene(wrongSport)

        let cloneFailure = ReplayBundledAssetSet(
            sport: .rower,
            rigVisualProvider: rowerSet.rigVisualProvider,
            athleteTemplate: rowerSet.athleteTemplate,
            athleteInstanceFactory: { _, _, _, _ in nil }
        )
        let failedClone = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.ultra.configuration,
            effectiveQuality: .ultra,
            bundledAssetSet: cloneFailure
        )
        assertCompleteProceduralScene(failedClone)
    }

    func testValidatedV4AthleteRunsAtEveryQualityWhileEquipmentRemainsTiered() async throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loaded)
            for quality in ReplayRenderQuality.allCases {
                let scene = Replay3DSceneBuilder.buildScene(
                    sport: sport,
                    colorScheme: .dark,
                    configuration: quality.configuration,
                    effectiveQuality: quality,
                    bundledAssetSet: assetSet
                )

                XCTAssertTrue(scene.usesCanonicalAthlete, "\(sport.rawValue) \(quality)")
                XCTAssertEqual(
                    scene.visualSource,
                    quality == .high || quality == .ultra ? .bundled : .procedural,
                    "\(sport.rawValue) \(quality) equipment policy"
                )
                let live = try XCTUnwrap(
                    scene.liveRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
                )
                let rival = try XCTUnwrap(
                    scene.ghostRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
                )
                XCTAssertFalse(live === rival)
                XCTAssertNil(scene.liveRig.root.replayDescendant(named: "pelvis"))
                XCTAssertNil(scene.ghostRig.root.replayDescendant(named: "pelvis"))
            }
        }
    }

    func testEquipmentPreflightFailureSelectsOneProceduralRig() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let assetSet = try XCTUnwrap(loaded)
        let athlete = try XCTUnwrap(assetSet.makeAthleteInstance(
            sport: .rower,
            name: "preflight-athlete",
            isRival: false,
            quality: .ultra
        ))
        let missingSource = try XCTUnwrap(
            ReplayRigVisualCatalog.slots(for: .rower).first?.sourceName
        )
        let rig = ReplaySportRigFactory.build(
            sport: .rower,
            into: ModelEntity(),
            accent: .green,
            opacity: 1,
            visualProvider: FailingRigVisualProvider(missingSource: missingSource),
            canonicalAthlete: athlete
        )

        XCTAssertNotNil(rig.root.replayDescendant(named: "pelvis"))
        XCTAssertNotNil(rig.root.replayDescendant(named: "hull"))
        XCTAssertNil(rig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName))
        XCTAssertNil(rig.root.replayDescendant(named: "bundled-test-visual"))
    }

    func testWrongSportPreflightSelectsOneCompleteProceduralRig() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let rowerSet = try XCTUnwrap(loaded)
        let rowerPreflight = try XCTUnwrap(ReplayPreflightRigVisualProvider(
            base: rowerSet.rigVisualProvider,
            sport: .rower
        ))
        let builtBikeAthlete = await rowerSet.athleteTemplate.makeInstance(
            sport: .bike,
            name: "wrong-preflight-athlete",
            isRival: false,
            quality: .ultra
        )
        let bikeAthlete = try XCTUnwrap(builtBikeAthlete)

        XCTAssertTrue(rowerPreflight.isComplete(for: .rower))
        XCTAssertFalse(rowerPreflight.isComplete(for: .bike))
        XCTAssertEqual(
            rowerPreflight.logicalNames,
            Set(ReplayRigVisualCatalog.slots(for: .rower).map(\.logicalName))
        )
        XCTAssertFalse(rowerPreflight.logicalNames.contains("visual-programming-error"))

        let rig = ReplaySportRigFactory.build(
            sport: .bike,
            into: ModelEntity(),
            accent: .green,
            opacity: 1,
            visualProvider: rowerPreflight,
            canonicalAthlete: bikeAthlete
        )

        XCTAssertNotNil(rig.root.replayDescendant(named: "pelvis"))
        XCTAssertNotNil(rig.root.replayDescendant(named: "chainStay-L"))
        XCTAssertNil(rig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName))
    }

    func testVisualCatalogMapsEveryLogicalSlotToAuthoredEquipment() {
        let expectedCounts: [Sport: Int] = [.rower: 6, .skierg: 8, .bike: 4]
        for sport in ReplayAssetCatalog.supportedSports {
            let slots = ReplayRigVisualCatalog.slots(for: sport)
            XCTAssertEqual(slots.count, expectedCounts[sport])
            XCTAssertEqual(Set(slots.map(\.logicalName)).count, slots.count)
            XCTAssertTrue(slots.allSatisfy { $0.logicalName.hasPrefix("visual-") })
            XCTAssertTrue(slots.allSatisfy { $0.sourceName.hasPrefix("equipment:") })
        }
    }

    func testPreflightExhaustsTheExactCatalogForEverySport() async throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loaded)
            let preflight = try XCTUnwrap(ReplayPreflightRigVisualProvider(
                base: assetSet.rigVisualProvider,
                sport: sport
            ))
            let expected = Set(ReplayRigVisualCatalog.slots(for: sport).map(\.logicalName))
            XCTAssertEqual(preflight.sport, sport)
            XCTAssertEqual(preflight.logicalNames, expected)
            XCTAssertTrue(preflight.isComplete(for: sport))
            for logicalName in expected {
                XCTAssertNotNil(preflight.cloneVisual(named: logicalName))
            }
        }
    }

    func testBundledRigsConsumeEveryValidatedCompositeAndLeafSlot() async throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loaded)
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.ultra.configuration,
                effectiveQuality: .ultra,
                bundledAssetSet: assetSet
            )
            XCTAssertEqual(scene.visualSource, .bundled)

            let multiplicities = Dictionary(
                grouping: ReplayRigVisualCatalog.slots(for: sport),
                by: \.sourceName
            ).mapValues(\.count)
            for (sourceName, expectedCount) in multiplicities {
                let exportedName = sourceName
                    .replacingOccurrences(of: ":", with: "_")
                    .replacingOccurrences(of: "-", with: "_")
                XCTAssertGreaterThanOrEqual(
                    countEntities(named: exportedName, in: scene.liveRig.root),
                    expectedCount,
                    "Bundled \(sport.rawValue) omitted validated runtime slot \(sourceName)"
                )
            }

            for composite in ReplayAssetCatalog.requiredCompositeSourceNames(for: sport) {
                for part in ReplayAssetCatalog.requiredParts[composite] ?? [] {
                    let exportedPart = "\(composite):\(part)"
                        .replacingOccurrences(of: ":", with: "_")
                        .replacingOccurrences(of: "-", with: "_")
                    XCTAssertNotNil(
                        scene.liveRig.root.replayDescendant(named: exportedPart),
                        "Bundled \(sport.rawValue) omitted authored part \(part)"
                    )
                }
            }
        }
    }

    func testGripControllerSourceContainsNoPinnedHandOrCupBoneLiterals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/RowPlayStudio/Views/Replay3D/ReplayAthleteGripController.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in [
            "v4LeftHand",
            "v4RightHand",
            "v4LeftFingers",
            "v4RightFingers",
        ] {
            XCTAssertFalse(source.contains(forbidden), "Found pinned controller literal: \(forbidden)")
        }
    }

    func testGripControllersInstallCompleteClosuresAndResolveChannelNativeContacts() async throws {
        let loaded = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loaded)
        for sport in ReplayAssetCatalog.supportedSports {
            let built = await template.makeInstance(
                sport: sport,
                name: "grip-probe",
                isRival: false,
                quality: .ultra
            )
            let instance = try XCTUnwrap(built)
            for side in ReplayHandSide.allCases {
                let closure = instance.gripController.closure(forSide: side)
                XCTAssertEqual(closure.poses.count, 15)
                XCTAssertEqual(closure.contacts.count, 5)
                for pose in closure.poses {
                    XCTAssertNotNil(instance.gripController.solvedRotation(forHelper: pose.helper))
                }
                let role: ReplayAthleteContactRole = side == .left ? .leftHand : .rightHand
                let authored = try XCTUnwrap(instance.authoredContactSpec(role: role))
                let resolved = try XCTUnwrap(instance.resolvedContactSpec(role: role))
                var authoredPalm = ReplayGripGeometry.handPalmContact
                authoredPalm.x *= side.rawValue
                XCTAssertEqual(authored.localOffset.x, authoredPalm.x, accuracy: 1e-9)
                XCTAssertEqual(authored.localOffset.y, authoredPalm.y, accuracy: 1e-9)
                XCTAssertEqual(authored.localOffset.z, authoredPalm.z, accuracy: 1e-9)
                XCTAssertEqual(resolved.bone, authored.bone)
                XCTAssertEqual(resolved.role, role)
                XCTAssertEqual(resolved.model, .sportGripChannel)
                XCTAssertEqual(
                    instance.gripController.terminalHandBone(forSide: side),
                    authored.bone
                )
                let cupHelper = instance.gripController.cupHelper(forSide: side)
                XCTAssertEqual(instance.contract.parentName(of: cupHelper), authored.bone)
                XCTAssertTrue(instance.contract.helpers.contains { $0.name == cupHelper })

                let expected: SIMD3<Double>
                switch sport {
                case .rower:
                    expected = ReplayGripGeometry.handChannelCentre(
                        radius: ReplayRowGripContract.scullGrip.radius,
                        side: side
                    )
                case .skierg:
                    var centre = ReplayGripGeometry.handFistCentre
                    centre.x *= side.rawValue
                    expected = centre
                case .bike:
                    expected = ReplayGripGeometry.handChannelCentre(
                        radius: ReplayBikeGripContract.hoodRadius,
                        side: side
                    )
                }
                XCTAssertEqual(resolved.localOffset.x, expected.x, accuracy: 1e-9)
                XCTAssertEqual(resolved.localOffset.y, expected.y, accuracy: 1e-9)
                XCTAssertEqual(resolved.localOffset.z, expected.z, accuracy: 1e-9)
            }

            for role in [ReplayAthleteContactRole.leftFoot, .rightFoot] {
                let authored = try XCTUnwrap(instance.authoredContactSpec(role: role))
                let resolved = try XCTUnwrap(instance.resolvedContactSpec(role: role))
                XCTAssertEqual(resolved.bone, authored.bone)
                XCTAssertEqual(resolved.role, role)
                XCTAssertEqual(resolved.model, .authoredSole)
                XCTAssertEqual(resolved.localOffset, authored.localOffset)
            }
        }
    }

    func testBundledScenesSeekAllSportsWithIndependentLiveAndRivalInstances() async throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let loadedSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loadedSet)
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.ultra.configuration,
                effectiveQuality: .ultra,
                bundledAssetSet: assetSet
            )
            XCTAssertEqual(scene.visualSource, .bundled)

            let liveMesh = try XCTUnwrap(
                scene.liveRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
            )
            let rivalMesh = try XCTUnwrap(
                scene.ghostRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
            )
            XCTAssertFalse(liveMesh === rivalMesh)

            let camera = ReplayCameraController()
            for (frame, phase) in [0.0, 0.8, 2.1, 4.9].enumerated() {
                let livePose = ReplayStrokePose.fallback(sport: sport, phase: phase, rate: 28)
                let rivalPose = ReplayStrokePose.fallback(sport: sport, phase: phase + 0.4, rate: 27)
                let updated = Replay3DSceneBuilder.updateScene(
                    container: scene,
                    livePose: livePose,
                    liveDistance: Double(frame),
                    sport: sport,
                    ghostPose: rivalPose,
                    ghostDistance: Double(frame) * 0.9,
                    ghostVisible: true,
                    reduceMotion: false,
                    deltaTime: 1.0 / 60.0,
                    playbackTickGeneration: UInt64(frame + 1),
                    isPlaying: true,
                    cameraController: camera,
                    cameraPreset: .chase,
                    cameraResetGeneration: 0,
                    replayDiscontinuityGeneration: 0
                )
                XCTAssertTrue(
                    updated,
                    "Expected finite in-contract contacts for \(sport.rawValue) phase \(phase); "
                        + "result=\(String(describing: ReplayAthleteContactSolver.lastResultForTesting))"
                )
                if updated {
                    assertCanonicalContacts(in: scene.liveRig, sport: sport)
                    assertCanonicalContacts(in: scene.ghostRig, sport: sport)
                    let metrics = try XCTUnwrap(ReplayAthleteContactSolver.lastMetricsForTesting)
                    XCTAssertEqual(metrics.topologyBuilds, 0)
                    XCTAssertEqual(metrics.fullWorkspaceBuilds, 1)
                    XCTAssertLessThanOrEqual(
                        metrics.jointMatrixEvaluations,
                        512,
                        "Contact pass exceeded its deterministic matrix budget"
                    )
                    if sport == .bike,
                       case .applied(let error, _) = ReplayAthleteContactSolver.lastResultForTesting {
                        XCTAssertLessThanOrEqual(
                            error.maximumGripChannelError,
                            ReplayAthleteContactSolver.gripChannelContactBudgetMeters
                        )
                        XCTAssertLessThanOrEqual(
                            error.maximumSoleError,
                            ReplayAthleteContactSolver.reachContactBudgetMeters
                        )
                        XCTAssertLessThanOrEqual(
                            error.pelvis,
                            ReplayAthleteContactSolver.reachContactBudgetMeters
                        )
                    }
                }
            }
        }
    }

    func testBundledRigWithoutMotionFailsClosedWithoutProceduralMutation() async throws {
        let loadedSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let assetSet = try XCTUnwrap(loadedSet)
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.ultra.configuration,
            effectiveQuality: .ultra,
            bundledAssetSet: assetSet
        )
        let mesh = try XCTUnwrap(
            scene.liveRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
        )
        let before = try XCTUnwrap(
            mesh.components[SkeletalPosesComponent.self]?.poses.default
        ).jointTransforms
        let pose = ReplayRigPoseSolver.solve(
            sport: .rower,
            strokePose: .fallback(sport: .rower, phase: 1.2, rate: 28),
            distance: 0,
            reduceMotion: false
        )

        XCTAssertEqual(scene.liveRig.applyPose(pose, motion: nil), .failed(.missingMotionSample))
        let after = try XCTUnwrap(
            mesh.components[SkeletalPosesComponent.self]?.poses.default
        ).jointTransforms
        XCTAssertEqual(before.map(\.translation), after.map(\.translation))
        XCTAssertEqual(before.map(\.rotation.vector), after.map(\.rotation.vector))
        XCTAssertNil(scene.liveRig.root.replayDescendant(named: "pelvis"))
        XCTAssertTrue(scene.liveRig.consumeCanonicalRuntimeFailure())
    }

    func testMalformedContactHierarchyFailsBeforeSolve() {
        let failure = ReplayAthleteContactSolver.hierarchyFailureForTesting(
            jointNames: ["v4Hips/v4Spine"]
        )
        guard case .malformedHierarchy = failure else {
            return XCTFail("Expected missing-parent hierarchy failure, got \(String(describing: failure))")
        }
    }

    func testUnreachableContactPassRestoresTheSampledPose() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let assetSet = try XCTUnwrap(loaded)
        let instance = try XCTUnwrap(assetSet.makeAthleteInstance(
            sport: .rower,
            name: "atomic-contact-probe",
            isRival: false,
            quality: .ultra
        ))
        let space = Entity()
        instance.attach(to: space)
        instance.captureBaseRootTransform()
        let beforePose = try XCTUnwrap(instance.currentConstraintPose())
        let beforeRoot = instance.root.transform

        let result = ReplayAthleteContactSolver.solve(
            instance: instance,
            targets: ReplayAthleteContactTargets(
                pelvis: .zero,
                leftHand: SIMD3(-100, 100, 100),
                rightHand: SIMD3(100, 100, 100),
                leftFoot: SIMD3(-100, -100, 100),
                rightFoot: SIMD3(100, -100, 100)
            ),
            relativeTo: space
        )

        guard case .failed(.residualExceeded, _) = result else {
            return XCTFail("Expected typed residual failure, got \(result)")
        }
        let afterPose = try XCTUnwrap(instance.currentConstraintPose())
        XCTAssertEqual(beforePose.jointTransforms.map(\.translation), afterPose.jointTransforms.map(\.translation))
        XCTAssertEqual(beforePose.jointTransforms.map(\.rotation.vector), afterPose.jointTransforms.map(\.rotation.vector))
        XCTAssertEqual(beforeRoot.translation, instance.root.transform.translation)
        XCTAssertEqual(beforeRoot.rotation.vector, instance.root.transform.rotation.vector)
    }

    func testMissingSkeletalPoseTriggersOneShotRuntimeFailure() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let assetSet = try XCTUnwrap(loaded)
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.ultra.configuration,
            effectiveQuality: .ultra,
            bundledAssetSet: assetSet
        )
        let mesh = try XCTUnwrap(
            scene.liveRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
        )
        mesh.components.remove(SkeletalPosesComponent.self)
        let stroke = ReplayStrokePose.fallback(sport: .rower, phase: 0.4, rate: 28)
        scene.liveRig.applyPose(
            ReplayRigPoseSolver.solve(
                sport: .rower,
                strokePose: stroke,
                distance: 0,
                reduceMotion: false
            ),
            motion: ReplayAthleteMotionSample(strokePose: stroke)
        )
        XCTAssertTrue(scene.liveRig.consumeCanonicalRuntimeFailure())
        XCTAssertFalse(scene.liveRig.consumeCanonicalRuntimeFailure())

        XCTAssertFalse(Replay3DSceneBuilder.updateScene(
            container: scene,
            livePose: stroke,
            liveDistance: 0,
            sport: .rower,
            ghostPose: nil,
            ghostDistance: 0,
            ghostVisible: false,
            reduceMotion: false,
            deltaTime: 1.0 / 60.0,
            playbackTickGeneration: 1,
            isPlaying: true,
            cameraController: ReplayCameraController(),
            cameraPreset: .chase,
            cameraResetGeneration: 0,
            replayDiscontinuityGeneration: 0
        ))
        XCTAssertFalse(scene.liveRig.consumeCanonicalRuntimeFailure())
    }

    func testLowTierCanonicalRuntimeFailureStillFailsClosed() async throws {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .skierg)
        let assetSet = try XCTUnwrap(loaded)
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .skierg,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.low.configuration,
            effectiveQuality: .low,
            bundledAssetSet: assetSet
        )
        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertTrue(scene.usesCanonicalAthlete)
        let mesh = try XCTUnwrap(
            scene.liveRig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName)
        )
        mesh.components.remove(SkeletalPosesComponent.self)
        let stroke = ReplayStrokePose.fallback(sport: .skierg, phase: 0.2, rate: 28)

        XCTAssertFalse(Replay3DSceneBuilder.updateScene(
            container: scene,
            livePose: stroke,
            liveDistance: 0,
            sport: .skierg,
            ghostPose: nil,
            ghostDistance: 0,
            ghostVisible: false,
            reduceMotion: false,
            deltaTime: 1.0 / 60.0,
            playbackTickGeneration: 1,
            isPlaying: true,
            cameraController: ReplayCameraController(),
            cameraPreset: .chase,
            cameraResetGeneration: 0,
            replayDiscontinuityGeneration: 0
        ))
        XCTAssertFalse(scene.liveRig.consumeCanonicalRuntimeFailure())
    }

    func testProceduralRigsKeepEquipmentContactsAndFiniteTransforms() {
        let rower = buildProceduralRig(sport: .rower)
        rower.applyPose(.rower(ReplayRowerRigPose(
            joints: ReplayAthleteJointPose(
                torsoLean: 0.21,
                shoulderFlexL: -0.18,
                shoulderFlexR: -0.18,
                kneeFlexL: 0.35,
                kneeFlexR: 0.35
            ),
            seatZ: -0.12,
            handleY: 0.72,
            handleZ: 0.53,
            oarSweep: 0.2,
            oarFeather: -0.06
        )))
        assertContact(named: "hand-L", with: "scull-grip-anchor-L", in: rower)
        assertContact(named: "hand-R", with: "scull-grip-anchor-R", in: rower)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: rower)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: rower)
        XCTAssertTrue(allTransformsAreFinite(in: rower.root))

        let ski = buildProceduralRig(sport: .skierg)
        ski.applyPose(.skierg(ReplaySkiErgRigPose(
            joints: ReplayAthleteJointPose(
                torsoLean: 0.12,
                shoulderFlexL: 0.22,
                shoulderFlexR: 0.22,
                kneeFlexL: 0.16,
                kneeFlexR: 0.16
            ),
            hipCompression: 0.25,
            handleY: 0.57,
            handleZ: 0.18,
            poleRotation: -0.22
        )))
        assertContact(named: "hand-L", with: "pole-grip-anchor-L", in: ski)
        assertContact(named: "hand-R", with: "pole-grip-anchor-R", in: ski)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: ski)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: ski)
        XCTAssertTrue(allTransformsAreFinite(in: ski.root))

        let bike = buildProceduralRig(sport: .bike)
        bike.applyPose(.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(
                torsoTilt: 0.04,
                shoulderFlexL: -0.25,
                shoulderFlexR: -0.25,
                kneeFlexL: 0.42,
                kneeFlexR: -0.22
            ),
            crankAngle: .pi / 3,
            wheelAngle: .pi / 4,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
            pedalPosR: ReplayPedalPosition(y: -0.18, z: 0),
            riderSway: 0.03
        )))
        assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: bike)
        assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: bike)
        assertContact(named: "foot-L", with: "pedal-L", in: bike)
        assertContact(named: "foot-R", with: "pedal-R", in: bike)
        XCTAssertTrue(allTransformsAreFinite(in: bike.root))
    }

    func testProceduralBikeKeepsChainStaysAndGhostsDoNotMutateLiveMaterials() {
        let live = buildProceduralRig(sport: .bike)
        let ghost = buildProceduralRig(sport: .bike)
        XCTAssertNotNil(live.root.replayDescendant(named: "chainStay-L"))
        XCTAssertNotNil(live.root.replayDescendant(named: "chainStay-R"))

        let liveBefore = materialAlphas(in: live.root)
        XCTAssertFalse(liveBefore.isEmpty)
        ghost.applyGhostTranslucency()
        XCTAssertEqual(materialAlphas(in: live.root), liveBefore)
        XCTAssertTrue(materialAlphas(in: ghost.root).allSatisfy { $0 <= 0.46 })
    }

    private func buildProceduralRig(sport: Sport) -> ReplaySportRig {
        ReplaySportRigFactory.build(
            sport: sport,
            into: ModelEntity(),
            accent: .green,
            opacity: 1,
            visualProvider: nil,
            canonicalAthlete: nil
        )
    }

    private func assertCompleteProceduralScene(
        _ scene: Replay3DSceneContainer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(scene.visualSource, .procedural, file: file, line: line)
        XCTAssertFalse(scene.usesCanonicalAthlete, file: file, line: line)
        XCTAssertNotNil(
            scene.liveRig.root.replayDescendant(named: "pelvis"),
            file: file,
            line: line
        )
        XCTAssertNotNil(
            scene.ghostRig.root.replayDescendant(named: "pelvis"),
            file: file,
            line: line
        )
        XCTAssertNil(
            scene.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName),
            file: file,
            line: line
        )
    }

    private func assertCanonicalContacts(
        in rig: ReplaySportRig,
        sport: Sport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let anchors: [(String, String)]
        switch sport {
        case .rower:
            anchors = [
                ("hand-L", "scull-grip-anchor-L"),
                ("hand-R", "scull-grip-anchor-R"),
            ]
        case .skierg:
            anchors = [
                ("hand-L", "pole-grip-anchor-L"),
                ("hand-R", "pole-grip-anchor-R"),
            ]
        case .bike:
            anchors = [
                ("hand-L", "handle-grip-anchor-L"),
                ("hand-R", "handle-grip-anchor-R"),
            ]
        }
        for (contactName, anchorName) in anchors {
            guard let contact = rig.root.replayDescendant(named: contactName),
                  let anchor = rig.root.replayDescendant(named: anchorName) else {
                return XCTFail(
                    "Missing \(contactName) or \(anchorName)",
                    file: file,
                    line: line
                )
            }
            XCTAssertLessThanOrEqual(
                simd_distance(
                    contact.position(relativeTo: rig.root),
                    anchor.position(relativeTo: rig.root)
                ),
                ReplayAthleteContactSolver.gripChannelContactBudgetMeters,
                file: file,
                line: line
            )
        }
        let footAnchors = sport == .bike
            ? [("foot-L", "pedal-L"), ("foot-R", "pedal-R")]
            : [("foot-L", "foot-anchor-L"), ("foot-R", "foot-anchor-R")]
        for (contactName, anchorName) in footAnchors {
            guard let contact = rig.root.replayDescendant(named: contactName),
                  let anchor = rig.root.replayDescendant(named: anchorName) else {
                return XCTFail(
                    "Missing \(contactName) or \(anchorName)",
                    file: file,
                    line: line
                )
            }
            XCTAssertLessThanOrEqual(
                simd_distance(
                    contact.position(relativeTo: rig.root),
                    anchor.position(relativeTo: rig.root)
                ),
                ReplayAthleteContactSolver.reachContactBudgetMeters,
                file: file,
                line: line
            )
        }
    }

    private func assertContact(
        named bodyPartName: String,
        with anchorName: String,
        in rig: ReplaySportRig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let bodyPart = rig.root.replayDescendant(named: bodyPartName),
              let anchor = rig.root.replayDescendant(named: anchorName) else {
            return XCTFail("Missing \(bodyPartName) or \(anchorName)", file: file, line: line)
        }
        let bodyPosition = bodyPart.position(relativeTo: rig.root)
        let anchorPosition = anchor.position(relativeTo: rig.root)
        XCTAssertEqual(bodyPosition.x, anchorPosition.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(bodyPosition.y, anchorPosition.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(bodyPosition.z, anchorPosition.z, accuracy: 0.0001, file: file, line: line)
    }

    private func allTransformsAreFinite(in entity: Entity) -> Bool {
        let position = entity.position
        let orientation = entity.orientation
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              orientation.vector.x.isFinite, orientation.vector.y.isFinite,
              orientation.vector.z.isFinite, orientation.vector.w.isFinite else {
            return false
        }
        return entity.children.allSatisfy(allTransformsAreFinite)
    }

    private func countEntities(named name: String, in entity: Entity) -> Int {
        (entity.name == name ? 1 : 0)
            + entity.children.reduce(0) { $0 + countEntities(named: name, in: $1) }
    }

    private func materialAlphas(in entity: Entity) -> [Float] {
        var values: [Float] = []
        if let model = entity.components[ModelComponent.self] {
            for material in model.materials {
                if let simple = material as? SimpleMaterial {
                    values.append(Float(simple.color.tint.cgColor.alpha))
                } else if let pbr = material as? PhysicallyBasedMaterial {
                    values.append(Float(pbr.baseColor.tint.cgColor.alpha))
                } else if let unlit = material as? UnlitMaterial {
                    values.append(Float(unlit.color.tint.cgColor.alpha))
                }
            }
        }
        for child in entity.children {
            values.append(contentsOf: materialAlphas(in: child))
        }
        return values
    }
}

@MainActor
private final class FailingRigVisualProvider: ReplayRigVisualProvider {
    let usesBundledAssets = true
    private let missingSource: String

    init(missingSource: String) {
        self.missingSource = missingSource
    }

    func cloneVisual(named name: String) -> Entity? {
        guard name != missingSource else { return nil }
        let entity = ModelEntity(
            mesh: .generateBox(size: 0.1),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        entity.name = "bundled-test-visual"
        return entity
    }
}
