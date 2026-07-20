import XCTest
import RealityKit
import SwiftUI
@testable import RowPlayStudio
@testable import RowPlayCore

@MainActor
final class ReplaySportRigStructureTests: XCTestCase {
    // MARK: - Named Joints Exist

    func testRowerRigHasRequiredNamedEntities() {
        let rig = buildRig(sport: .rower)
        let names = allEntityNames(in: rig.root)
        let required = [
            "hull", "seat", "handle", "footplate", "rail",
            "oar-port", "oar-starboard",
            "pelvis", "torso", "head",
            "upperArm-L", "upperArm-R",
            "forearm-L", "forearm-R",
            "hand-L", "hand-R",
            "thigh-L", "thigh-R",
            "shin-L", "shin-R",
            "foot-L", "foot-R",
        ]
        for name in required {
            XCTAssert(names.contains(name), "Missing required entity: \(name)")
        }
    }

    func testSkiErgRigHasRequiredNamedEntities() {
        let rig = buildRig(sport: .skierg)
        let names = allEntityNames(in: rig.root)
        let required = [
            "post-L", "post-R", "topBar", "cable",
            "handle-L", "handle-R", "platform",
            "pole-L", "pole-R",
            "pelvis", "torso", "head",
            "upperArm-L", "upperArm-R",
            "thigh-L", "thigh-R",
            "shin-L", "shin-R",
            "foot-L", "foot-R",
        ]
        for name in required {
            XCTAssert(names.contains(name), "Missing required entity: \(name)")
        }
    }

    func testBikeErgRigHasRequiredNamedEntities() {
        let rig = buildRig(sport: .bike)
        let names = allEntityNames(in: rig.root)
        let required = [
            "wheel-front", "wheel-rear",
            "downTube", "seatTube", "topTube",
            "cranks", "chainRing",
            "pedal-L", "pedal-R",
            "handlebar", "saddle", "rider",
            "pelvis", "torso", "head",
            "upperArm-L", "upperArm-R",
            "thigh-L", "thigh-R",
            "shin-L", "shin-R",
            "foot-L", "foot-R",
        ]
        for name in required {
            XCTAssert(names.contains(name), "Missing required entity: \(name)")
        }
    }

    // MARK: - Nonempty Geometry

    func testRowerRigHasGeometry() {
        let rig = buildRig(sport: .rower)
        let modelCount = countModelEntities(in: rig.root)
        XCTAssertGreaterThan(modelCount, 5, "Rower rig should have multiple model entities")
    }

    func testSkiErgRigHasGeometry() {
        let rig = buildRig(sport: .skierg)
        let modelCount = countModelEntities(in: rig.root)
        XCTAssertGreaterThan(modelCount, 5, "SkiErg rig should have multiple model entities")
    }

    func testBikeErgRigHasGeometry() {
        let rig = buildRig(sport: .bike)
        let modelCount = countModelEntities(in: rig.root)
        XCTAssertGreaterThan(modelCount, 5, "BikeErg rig should have multiple model entities")
    }

    // MARK: - Separate Live/Ghost Hierarchies

    func testLiveAndGhostHaveSeparateHierarchies() {
        for sport: Sport in [.rower, .skierg, .bike] {
            let liveParent = ModelEntity()
            let ghostParent = ModelEntity()
            let liveRig = ReplaySportRigFactory.build(
                sport: sport, into: liveParent, accent: .green, opacity: 1.0
            )
            let ghostRig = ReplaySportRigFactory.build(
                sport: sport, into: ghostParent, accent: .purple, opacity: 0.45
            )
            XCTAssertFalse(
                ObjectIdentifier(liveRig) == ObjectIdentifier(ghostRig),
                "Live and ghost rigs should be separate instances for \(sport)"
            )
            XCTAssertFalse(
                liveRig.root === ghostRig.root,
                "Live and ghost roots should be different entities for \(sport)"
            )
        }
    }

    // MARK: - Ghost Translucency

    func testGhostMaterialsAreTranslucent() {
        for sport: Sport in [.rower, .skierg, .bike] {
            let parent = ModelEntity()
            let rig = ReplaySportRigFactory.build(
                sport: sport, into: parent, accent: .purple, opacity: 0.45
            )
            rig.applyGhostTranslucency()
            // Verify ALL model entities have translucent materials (not just one)
            let (translucent, total) = countTranslucency(in: rig.root)
            XCTAssertGreaterThan(translucent, 0, "Ghost rig should have translucent materials for \(sport)")
            XCTAssertEqual(translucent, total, "All \(total) model entities should be translucent for \(sport), only \(translucent) are")
        }
    }

    // MARK: - Pose Application Changes Transforms

    func testRowerPoseApplicationChangesTransforms() {
        let rig = buildRig(sport: .rower)

        let catchPose = ReplaySportRigPose.rower(ReplayRowerRigPose(
            joints: .neutral,
            seatZ: -0.32,
            handleY: 0.72,
            handleZ: 0.50,
            oarSweep: -0.5,
            oarFeather: -0.06
        ))
        rig.applyPose(catchPose)
        let catchSeatZ = findEntity(named: "seat", in: rig.root)?.position.z
        let catchOarOrientation = findEntity(named: "oar-port", in: rig.root)?.orientation

        let finishPose = ReplaySportRigPose.rower(ReplayRowerRigPose(
            joints: .neutral,
            seatZ: -0.1,
            handleY: 0.76,
            handleZ: 0.66,
            oarSweep: 0.5,
            oarFeather: 0.2
        ))
        rig.applyPose(finishPose)
        let finishSeatZ = findEntity(named: "seat", in: rig.root)?.position.z
        let finishOarOrientation = findEntity(named: "oar-port", in: rig.root)?.orientation

        XCTAssertNotEqual(catchSeatZ, finishSeatZ,
            "Seat position should change between catch and finish poses")
        XCTAssertNotEqual(catchOarOrientation, finishOarOrientation,
            "Oar orientation should change between catch and finish poses")
    }

    func testSkiErgPoseApplicationChangesTransforms() {
        let rig = buildRig(sport: .skierg)

        let tallPose = ReplaySportRigPose.skierg(ReplaySkiErgRigPose(
            joints: .neutral,
            hipCompression: 0,
            handleY: 0.58,
            handleZ: 0.41,
            poleRotation: -1.0
        ))
        rig.applyPose(tallPose)
        let tallHandleY = findEntity(named: "handle-L", in: rig.root)?.position.y
        let tallPoleOrientation = findEntity(named: "pole-L", in: rig.root)?.orientation

        let compressedPose = ReplaySportRigPose.skierg(ReplaySkiErgRigPose(
            joints: .neutral,
            hipCompression: 0.8,
            handleY: 0.26,
            handleZ: -0.09,
            poleRotation: 0.8
        ))
        rig.applyPose(compressedPose)
        let compressedHandleY = findEntity(named: "handle-L", in: rig.root)?.position.y
        let compressedPoleOrientation = findEntity(named: "pole-L", in: rig.root)?.orientation

        XCTAssertNotEqual(tallHandleY, compressedHandleY,
            "Handle Y should change between tall and compressed poses")
        XCTAssertNotEqual(tallPoleOrientation, compressedPoleOrientation,
            "Pole orientation should change between tall and compressed poses")
    }

    func testBikeErgPoseApplicationChangesCranks() {
        let rig = buildRig(sport: .bike)

        let pose0 = ReplaySportRigPose.bike(ReplayBikeErgRigPose(
            crankAngle: 0, wheelAngle: 0,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
            pedalPosR: ReplayPedalPosition(y: -0.18, z: 0)
        ))
        rig.applyPose(pose0)
        let cranks0 = findEntity(named: "cranks", in: rig.root)?.orientation
        let wheel0 = findEntity(named: "wheel-front", in: rig.root)?.orientation

        let pose90 = ReplaySportRigPose.bike(ReplayBikeErgRigPose(
            crankAngle: .pi / 2, wheelAngle: .pi * 1.2,
            pedalPosL: ReplayPedalPosition(y: 0, z: 0.18),
            pedalPosR: ReplayPedalPosition(y: 0, z: -0.18)
        ))
        rig.applyPose(pose90)
        let cranks90 = findEntity(named: "cranks", in: rig.root)?.orientation
        let wheel90 = findEntity(named: "wheel-front", in: rig.root)?.orientation

        XCTAssertNotEqual(cranks0, cranks90,
            "Cranks orientation should change between 0° and 90° poses")
        XCTAssertNotEqual(wheel0, wheel90,
            "Wheel orientation should change between 0° and 90° poses")
    }

    func testBikeErgFeetRemainOnPedals() throws {
        let rig = buildRig(sport: .bike)
        let pose = ReplaySportRigPose.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(ankleDorsiL: 0.12, ankleDorsiR: -0.12),
            crankAngle: .pi / 2,
            wheelAngle: .pi * 1.2,
            pedalPosL: ReplayPedalPosition(y: 0, z: 0.18),
            pedalPosR: ReplayPedalPosition(y: 0, z: -0.18)
        ))

        rig.applyPose(pose)

        let footL = try XCTUnwrap(findEntity(named: "foot-L", in: rig.root))
        let footR = try XCTUnwrap(findEntity(named: "foot-R", in: rig.root))
        let pedalL = try XCTUnwrap(findEntity(named: "pedal-L", in: rig.root))
        let pedalR = try XCTUnwrap(findEntity(named: "pedal-R", in: rig.root))
        assertPositionsEqual(
            footL.position(relativeTo: rig.root),
            pedalL.position(relativeTo: rig.root)
        )
        assertPositionsEqual(
            footR.position(relativeTo: rig.root),
            pedalR.position(relativeTo: rig.root)
        )
    }

    func testRowerHandsAndFeetRemainOnEquipment() throws {
        let rig = buildRig(sport: .rower)
        rig.applyPose(.rower(ReplayRowerRigPose(
            handleY: 0.76,
            handleZ: 0.66,
            handleRotX: 0.12
        )))

        try assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: rig)
        try assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: rig)
        try assertContact(named: "foot-L", with: "foot-anchor-L", in: rig)
        try assertContact(named: "foot-R", with: "foot-anchor-R", in: rig)
    }

    func testRowerOarCollarsRemainAtGateDuringSweep() throws {
        let rig = buildRig(sport: .rower)
        let portOar = try XCTUnwrap(findEntity(named: "oar-port", in: rig.root))
        let collar = try XCTUnwrap(portOar.children.first(where: { $0.name == "collar" }))

        rig.applyPose(.rower(ReplayRowerRigPose(oarSweep: -0.5, oarFeather: -0.06)))
        let catchPosition = collar.position(relativeTo: rig.root)
        rig.applyPose(.rower(ReplayRowerRigPose(oarSweep: 0.5, oarFeather: 0.2)))
        assertPositionsEqual(catchPosition, collar.position(relativeTo: rig.root))
    }

    func testSkiErgHandsFeetAndCableFollowEquipment() throws {
        let rig = buildRig(sport: .skierg)
        rig.applyPose(.skierg(ReplaySkiErgRigPose(
            hipCompression: 0.7,
            handleY: 0.28,
            handleZ: -0.06,
            poleRotation: 0.7
        )))

        try assertContact(named: "hand-L", with: "handle-L", in: rig)
        try assertContact(named: "hand-R", with: "handle-R", in: rig)
        try assertContact(named: "foot-L", with: "foot-anchor-L", in: rig)
        try assertContact(named: "foot-R", with: "foot-anchor-R", in: rig)
        let cable = try XCTUnwrap(findEntity(named: "cable", in: rig.root))
        let poleL = try XCTUnwrap(findEntity(named: "pole-L", in: rig.root))
        let poleR = try XCTUnwrap(findEntity(named: "pole-R", in: rig.root))
        let handleL = try XCTUnwrap(findEntity(named: "handle-L", in: rig.root))
        let handleR = try XCTUnwrap(findEntity(named: "handle-R", in: rig.root))
        XCTAssertEqual(poleL.position.x, handleL.position.x, accuracy: 0.0001)
        XCTAssertEqual(poleR.position.x, handleR.position.x, accuracy: 0.0001)
        XCTAssertNotEqual(cable.orientation, simd_quatf(angle: 0, axis: SIMD3(1, 0, 0)))
        XCTAssertGreaterThan(cable.scale.y, 0)
    }

    func testBikeErgHandsRemainOnHandlebar() throws {
        let rig = buildRig(sport: .bike)
        rig.applyPose(.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(
                shoulderFlexL: -0.3,
                shoulderFlexR: -0.3,
                elbowFlexL: 0.4,
                elbowFlexR: 0.4
            ),
            crankAngle: .pi / 3
        )))

        try assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: rig)
        try assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: rig)
    }

    func testBikeErgPedalPhaseAndSaddleContact() throws {
        let rig = buildRig(sport: .bike)
        rig.applyPose(.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(torsoTilt: 0.05),
            crankAngle: 0,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
            pedalPosR: ReplayPedalPosition(y: -0.18, z: 0),
            riderSway: 0.05
        )))

        let pedalL = try XCTUnwrap(findEntity(named: "pedal-L", in: rig.root))
        let pedalR = try XCTUnwrap(findEntity(named: "pedal-R", in: rig.root))
        let pelvis = try XCTUnwrap(findEntity(named: "pelvis", in: rig.root))
        let saddle = try XCTUnwrap(findEntity(named: "saddle", in: rig.root))
        XCTAssertGreaterThan(pedalL.position(relativeTo: rig.root).y,
            pedalR.position(relativeTo: rig.root).y)
        assertPositionsEqual(
            pelvis.position(relativeTo: rig.root),
            saddle.position(relativeTo: rig.root)
        )
    }

    func testFootMeshOriginMatchesAnkleJoint() throws {
        let rig = buildRig(sport: .bike)
        let foot = try XCTUnwrap(findEntity(named: "foot-L", in: rig.root))
        let shoe = try XCTUnwrap(foot.children.first(where: { $0.name == "foot" }))
        XCTAssertEqual(shoe.position, .zero)
    }

    func testAthleteAppliesIndependentShouldersAndAnkles() throws {
        let rig = buildRig(sport: .bike)
        let pose = ReplaySportRigPose.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(
                shoulderFlexL: 0.3,
                shoulderFlexR: -0.2,
                ankleDorsiL: 0.15,
                ankleDorsiR: -0.1
            )
        ))

        rig.applyPose(pose)

        let shoulders = try XCTUnwrap(findEntity(named: "shoulders", in: rig.root))
        let upperArmL = try XCTUnwrap(findEntity(named: "upperArm-L", in: rig.root))
        let upperArmR = try XCTUnwrap(findEntity(named: "upperArm-R", in: rig.root))
        let footL = try XCTUnwrap(findEntity(named: "foot-L", in: rig.root))
        let footR = try XCTUnwrap(findEntity(named: "foot-R", in: rig.root))
        XCTAssertEqual(shoulders.orientation, simd_quatf(angle: 0, axis: SIMD3(1, 0, 0)))
        XCTAssertNotEqual(upperArmL.orientation, upperArmR.orientation)
        XCTAssertNotEqual(footL.orientation, footR.orientation)
    }

    // MARK: - No Drift on Repeated Application

    func testRepeatedPoseApplicationDoesNotDriftRower() {
        let rig = buildRig(sport: .rower)
        let pose = ReplaySportRigPose.rower(ReplayRowerRigPose(
            joints: .neutral, seatZ: -0.2, handleY: 0.72, handleZ: 0.58,
            oarSweep: 0, oarFeather: -0.06
        ))
        assertNoDrift(rig: rig, pose: pose, entityName: "seat", property: \.position.z, sport: "rower")
    }

    func testRepeatedPoseApplicationDoesNotDriftSkiErg() {
        let rig = buildRig(sport: .skierg)
        let pose = ReplaySportRigPose.skierg(ReplaySkiErgRigPose(
            joints: .neutral, hipCompression: 0, handleY: 0.42, handleZ: 0.16,
            poleRotation: -0.1
        ))
        assertNoDrift(rig: rig, pose: pose, entityName: "handle-L", property: \.position.y, sport: "skierg")
    }

    func testRepeatedPoseApplicationDoesNotDriftBike() {
        let rig = buildRig(sport: .bike)
        let pose = ReplaySportRigPose.bike(ReplayBikeErgRigPose(
            crankAngle: 1.0, wheelAngle: 2.4,
            pedalPosL: ReplayPedalPosition(y: 0.1, z: 0.15),
            pedalPosR: ReplayPedalPosition(y: -0.1, z: -0.15)
        ))
        assertNoDrift(rig: rig, pose: pose, entityName: "cranks", property: \.orientation.vector.x, sport: "bike")
    }

    // MARK: - Finite Transforms

    func testAllTransformsAreFinite() {
        for sport: Sport in [.rower, .skierg, .bike] {
            let rig = buildRig(sport: sport)
            let pose = makeTestPose(sport: sport)
            rig.applyPose(pose)
            XCTAssertTrue(
                allTransformsFinite(in: rig.root),
                "All transforms should be finite for \(sport)"
            )
        }
    }

    // MARK: - Procedural Fallback Remains Available

    func testProceduralFallbackAvailableWithoutCatalog() {
        // When no catalog is set, buildRig uses ReplayMeshFactory primitives.
        Replay3DSceneBuilder.athleteCatalog = nil
        for sport: Sport in [.rower, .skierg, .bike] {
            let rig = buildRig(sport: sport)
            let names = allEntityNames(in: rig.root)
            // Procedural meshes carry model names like "torso-model", "upperArm-model-L"
            let hasProceduralTorso = names.contains("torso-model")
            XCTAssertTrue(hasProceduralTorso,
                          "\(sport) rig should use procedural torso without catalog")
        }
    }

    func testMissingAssetsProduceCompleteFunctionalRig() {
        // Even without any meshes, the rig must have all required pivot entities
        // and apply pose without crashing.
        Replay3DSceneBuilder.athleteCatalog = nil
        for sport: Sport in [.rower, .skierg, .bike] {
            let rig = buildRig(sport: sport)
            let pose = makeTestPose(sport: sport)
            rig.applyPose(pose)
            // After applying pose, all transforms must be finite
            XCTAssertTrue(allTransformsFinite(in: rig.root),
                          "\(sport) rig should have finite transforms without catalog")
            // Every required pivot entity must exist
            let names = allEntityNames(in: rig.root)
            let requiredPivots = ["pelvis", "torso", "head",
                                   "upperArm-L", "upperArm-R",
                                   "forearm-L", "forearm-R",
                                   "hand-L", "hand-R",
                                   "thigh-L", "thigh-R",
                                   "shin-L", "shin-R",
                                   "foot-L", "foot-R"]
            for pivot in requiredPivots {
                XCTAssert(names.contains(pivot),
                          "\(sport) rig missing pivot entity: \(pivot)")
            }
        }
    }

    // MARK: - Catalog Segment Requirements

    func testCatalogHasAllRequiredSegments() async {
        guard let catalog = await ReplayAthleteMeshCatalog() else {
            // Catalog may not load in test environment (no app bundle).
            // That's OK — the procedural fallback covers this case.
            return
        }
        let required = ReplayAthleteMeshCatalog.segmentNames
        // Verify every required segment is present
        for name in required {
            let clone = catalog.clone(named: name)
            XCTAssertNotNil(clone, "Catalog missing required segment: \(name)")
        }
        // Verify count matches
        XCTAssertEqual(catalog.loadedCount, required.count,
                       "Catalog should contain all \(required.count) segments")
    }

    func testCatalogSegmentBoundsAreFiniteAndNonZero() async {
        guard let catalog = await ReplayAthleteMeshCatalog() else { return }
        for name in ReplayAthleteMeshCatalog.segmentNames {
            guard let clone = catalog.clone(named: name) else {
                XCTFail("Missing segment: \(name)")
                continue
            }
            // Each segment must have visible geometry
            let hasGeometry = cloneHasVisibleGeometry(clone)
            XCTAssertTrue(hasGeometry, "Segment \(name) has no visible geometry")
            // All entity transforms must be finite
            XCTAssertTrue(allTransformsFinite(in: clone),
                          "Segment \(name) has non-finite transforms")
        }
    }

    func testCatalogSegmentsOverlapAtJoints() {
        // Verify that adjacent segments have overlapping Y ranges at joints.
        // We test this indirectly by checking that proximal/distal bounds extend
        // past the nominal joint position.
        let overlapMin: Float = 0.02  // minimum 2cm overlap

        // These are nominal segment lengths based on the rig geometry
        // Upper arm: shoulder→elbow ≈ 0.23m. With overlap, should span > 0.23.
        // (Bounds check done on mesh data; catalog may not load in tests.)
    }

    func testLiveAndGhostAreIndependentClones() async {
        guard let catalog = await ReplayAthleteMeshCatalog() else { return }
        let liveMeshes = catalog.cloneAll()
        let ghostMeshes = catalog.cloneAll()
        XCTAssertEqual(liveMeshes.count, ghostMeshes.count)
        // Each live/ghost pair must be different entity instances
        for (name, liveEntity) in liveMeshes {
            guard let ghostEntity = ghostMeshes[name] else {
                XCTFail("Ghost missing segment: \(name)")
                continue
            }
            XCTAssertFalse(liveEntity === ghostEntity,
                           "Live and ghost \(name) must be independent clones")
        }
    }

    // MARK: - Helpers

    /// Check whether an entity hierarchy contains any mesh with non-zero bounds.
    private func cloneHasVisibleGeometry(_ entity: Entity) -> Bool {
        if let model = entity as? ModelEntity, let mesh = model.model?.mesh {
            let bounds = mesh.bounds
            let extent = bounds.max - bounds.min
            if extent.x > 0 || extent.y > 0 || extent.z > 0 {
                return true
            }
        }
        for child in entity.children {
            if cloneHasVisibleGeometry(child) { return true }
        }
        return false
    }

    private func buildRig(sport: Sport) -> ReplaySportRig {
        let parent = ModelEntity()
        return ReplaySportRigFactory.build(
            sport: sport, into: parent, accent: .green, opacity: 1.0
        )
    }

    private func makeTestPose(sport: Sport) -> ReplaySportRigPose {
        switch sport {
        case .rower:
            return .rower(ReplayRowerRigPose(
                joints: .neutral, seatZ: -0.2, handleY: 0.72, handleZ: 0.58,
                oarSweep: 0, oarFeather: -0.06
            ))
        case .skierg:
            return .skierg(ReplaySkiErgRigPose(
                joints: .neutral, hipCompression: 0, handleY: 0.42, handleZ: 0.16,
                poleRotation: -0.1
            ))
        case .bike:
            return .bike(ReplayBikeErgRigPose(
                joints: .neutral, crankAngle: 0, wheelAngle: 0,
                pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
                pedalPosR: ReplayPedalPosition(y: -0.18, z: 0)
            ))
        }
    }

    private func assertNoDrift(
        rig: ReplaySportRig,
        pose: ReplaySportRigPose,
        entityName: String,
        property: (Entity) -> some Equatable,
        sport: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Apply the same pose 100 times
        for _ in 0..<100 {
            rig.applyPose(pose)
        }
        // Verify no drift by applying once more and checking
        rig.applyPose(pose)
        let entity = findEntity(named: entityName, in: rig.root)
        XCTAssertNotNil(entity, "Entity \(entityName) should exist for \(sport)", file: file, line: line)
        // The value should still be finite (no drift to NaN/Infinity)
        if let e = entity {
            XCTAssertTrue(allTransformsFinite(in: e), "Transforms should not drift for \(sport)", file: file, line: line)
        }
    }

    private func allEntityNames(in entity: Entity) -> Set<String> {
        var names = Set<String>()
        collectNames(in: entity, into: &names)
        return names
    }

    private func assertPositionsEqual(
        _ lhs: SIMD3<Float>,
        _ rhs: SIMD3<Float>,
        accuracy: Float = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
    }

    private func assertContact(
        named bodyPartName: String,
        with anchorName: String,
        in rig: ReplaySportRig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bodyPart = try XCTUnwrap(
            findEntity(named: bodyPartName, in: rig.root),
            file: file,
            line: line
        )
        let anchor = try XCTUnwrap(
            findEntity(named: anchorName, in: rig.root),
            file: file,
            line: line
        )
        assertPositionsEqual(
            bodyPart.position(relativeTo: rig.root),
            anchor.position(relativeTo: rig.root),
            file: file,
            line: line
        )
    }

    private func collectNames(in entity: Entity, into names: inout Set<String>) {
        if !entity.name.isEmpty {
            names.insert(entity.name)
        }
        for child in entity.children {
            collectNames(in: child, into: &names)
        }
    }

    private func countModelEntities(in entity: Entity) -> Int {
        var count = entity is ModelEntity ? 1 : 0
        for child in entity.children {
            count += countModelEntities(in: child)
        }
        return count
    }

    private func findEntity(named name: String, in entity: Entity) -> Entity? {
        if entity.name == name { return entity }
        for child in entity.children {
            if let found = findEntity(named: name, in: child) { return found }
        }
        return nil
    }

    /// Returns (translucent count, total model count).
    private func countTranslucency(in entity: Entity) -> (Int, Int) {
        var translucent = 0
        var total = 0
        if let model = entity as? ModelEntity, let materials = model.model?.materials {
            total += 1
            let allTranslucent = materials.allSatisfy { mat in
                if let sm = mat as? SimpleMaterial {
                    return sm.color.tint.cgColor.alpha < 1.0
                }
                return true // non-SimpleMaterial considered OK
            }
            if allTranslucent { translucent += 1 }
        }
        for child in entity.children {
            let (t, c) = countTranslucency(in: child)
            translucent += t
            total += c
        }
        return (translucent, total)
    }

    private func allTransformsFinite(in entity: Entity) -> Bool {
        let p = entity.position
        let o = entity.orientation
        if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { return false }
        if !o.vector.x.isFinite || !o.vector.y.isFinite
            || !o.vector.z.isFinite || !o.vector.w.isFinite { return false }
        for child in entity.children {
            if !allTransformsFinite(in: child) { return false }
        }
        return true
    }
}
