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
            // They should be different instances
            XCTAssertFalse(
                ObjectIdentifier(liveRig) == ObjectIdentifier(ghostRig),
                "Live and ghost rigs should be separate instances for \(sport)"
            )
            // Their roots should not be the same entity
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
            // Check that at least one model entity has translucent materials
            let hasTranslucent = checkTranslucency(in: rig.root)
            XCTAssertTrue(hasTranslucent, "Ghost rig should have translucent materials for \(sport)")
        }
    }

    // MARK: - Pose Application Changes Transforms

    func testRowerPoseApplicationChangesTransforms() {
        let rig = buildRig(sport: .rower)

        let catchPose = ReplaySportRigPose.rower(RowerRigPose(
            joints: .neutral,
            seatZ: -0.32,
            handleY: 0.72,
            handleZ: 0.50,
            oarSweep: -0.5,
            oarFeather: -0.06
        ))
        rig.applyPose(catchPose, reduceMotion: false)
        let catchSeatZ = findEntity(named: "seat", in: rig.root)?.position.z

        let finishPose = ReplaySportRigPose.rower(RowerRigPose(
            joints: .neutral,
            seatZ: -0.1,
            handleY: 0.76,
            handleZ: 0.66,
            oarSweep: 0.5,
            oarFeather: 0.2
        ))
        rig.applyPose(finishPose, reduceMotion: false)
        let finishSeatZ = findEntity(named: "seat", in: rig.root)?.position.z

        XCTAssertNotEqual(catchSeatZ, finishSeatZ,
            "Seat position should change between catch and finish poses")
    }

    func testBikeErgPoseApplicationChangesCranks() {
        let rig = buildRig(sport: .bike)

        let pose0 = ReplaySportRigPose.bike(BikeErgRigPose(
            crankAngle: 0, wheelAngle: 0,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0), pedalPosR: ReplayPedalPosition(y: -0.18, z: 0)
        ))
        rig.applyPose(pose0, reduceMotion: false)
        let cranks0 = findEntity(named: "cranks", in: rig.root)?.orientation

        let pose90 = ReplaySportRigPose.bike(BikeErgRigPose(
            crankAngle: .pi / 2, wheelAngle: .pi * 1.2,
            pedalPosL: ReplayPedalPosition(y: 0, z: 0.18), pedalPosR: ReplayPedalPosition(y: 0, z: -0.18)
        ))
        rig.applyPose(pose90, reduceMotion: false)
        let cranks90 = findEntity(named: "cranks", in: rig.root)?.orientation

        XCTAssertNotEqual(cranks0, cranks90,
            "Cranks orientation should change between 0° and 90° poses")
    }

    // MARK: - No Drift on Repeated Application

    func testRepeatedPoseApplicationDoesNotDrift() {
        let rig = buildRig(sport: .rower)
        let pose = ReplaySportRigPose.rower(RowerRigPose(
            joints: .neutral,
            seatZ: -0.2,
            handleY: 0.72,
            handleZ: 0.58,
            oarSweep: 0,
            oarFeather: -0.06
        ))

        // Apply the same pose 100 times
        for _ in 0..<100 {
            rig.applyPose(pose, reduceMotion: false)
        }

        // Check that the seat is still at the expected position
        let seat = findEntity(named: "seat", in: rig.root)
        XCTAssertNotNil(seat)
        XCTAssertEqual(seat!.position.z, Float(-0.2 + (-0.2)), accuracy: 0.001,
            "Seat should not drift after repeated application")
    }

    // MARK: - Finite Transforms

    func testAllTransformsAreFinite() {
        for sport: Sport in [.rower, .skierg, .bike] {
            let rig = buildRig(sport: sport)
            let pose = makeTestPose(sport: sport)
            rig.applyPose(pose, reduceMotion: false)
            XCTAssertTrue(
                allTransformsFinite(in: rig.root),
                "All transforms should be finite for \(sport)"
            )
        }
    }

    // MARK: - Helpers

    private func buildRig(sport: Sport) -> ReplaySportRig {
        let parent = ModelEntity()
        return ReplaySportRigFactory.build(
            sport: sport, into: parent, accent: .green, opacity: 1.0
        )
    }

    private func makeTestPose(sport: Sport) -> ReplaySportRigPose {
        switch sport {
        case .rower:
            return .rower(RowerRigPose(
                joints: .neutral, seatZ: -0.2, handleY: 0.72, handleZ: 0.58,
                oarSweep: 0, oarFeather: -0.06
            ))
        case .skierg:
            return .skierg(SkiErgRigPose(
                joints: .neutral, hipCompression: 0, handleY: 0.42, handleZ: 0.16,
                poleRotation: -0.1
            ))
        case .bike:
            return .bike(BikeErgRigPose(
                joints: .neutral, crankAngle: 0, wheelAngle: 0,
                pedalPosL: ReplayPedalPosition(y: 0.18, z: 0), pedalPosR: ReplayPedalPosition(y: -0.18, z: 0)
            ))
        }
    }

    private func allEntityNames(in entity: Entity) -> Set<String> {
        var names = Set<String>()
        collectNames(in: entity, into: &names)
        return names
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

    private func checkTranslucency(in entity: Entity) -> Bool {
        if let model = entity as? ModelEntity,
           let materials = model.model?.materials {
            for mat in materials {
                if let sm = mat as? SimpleMaterial,
                   sm.color.tint.cgColor.alpha < 1.0 {
                    return true
                }
            }
        }
        for child in entity.children {
            if checkTranslucency(in: child) { return true }
        }
        return false
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
