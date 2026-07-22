import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAthleteLibraryTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
        ReplayAssetLibrary.shared.resetCacheForTesting()
    }

    func testCanonicalUSDZLoadsAsSkinnedAthleteWithRequiredJoints() async throws {
        guard let template = await ReplayAthleteLibrary.shared.athleteTemplate() else {
            return XCTFail("Expected V4 athlete template")
        }
        XCTAssertEqual(template.jointNames, ReplayAthleteCatalog.orderedJointPaths)
        XCTAssertEqual(template.contract.orderedBoneNames.count, 19)
        XCTAssertEqual(template.sourceManifest.pinnedCommit, ReplayAthleteCatalog.pinnedCommit)

        let live = try XCTUnwrap(template.makeInstance(name: "live", opacity: 1))
        let rival = try XCTUnwrap(template.makeInstance(name: "rival", opacity: 0.45))
        XCTAssertTrue(live.hasFiniteJointTransforms())
        XCTAssertTrue(rival.hasFiniteJointTransforms())
        XCTAssertNotEqual(ObjectIdentifier(live.root), ObjectIdentifier(rival.root))
        XCTAssertNotNil(live.athleteEntity.components[ModelComponent.self])
        XCTAssertNotNil(live.athleteEntity.components[SkeletalPosesComponent.self])
        XCTAssertNotNil(live.leftHandContact)
        XCTAssertNotNil(live.rightFootContact)
    }

    func testIndependentLiveAndRivalClonesIsolateTranslucency() async throws {
        guard let template = await ReplayAthleteLibrary.shared.athleteTemplate() else {
            return XCTFail("Expected V4 athlete template")
        }
        let live = try XCTUnwrap(template.makeInstance(name: "live", opacity: 1))
        let rival = try XCTUnwrap(template.makeInstance(name: "rival", opacity: 0.45))

        let liveBefore = materialAlphas(in: live.root)
        XCTAssertFalse(liveBefore.isEmpty)
        XCTAssertTrue(liveBefore.allSatisfy { $0 > 0.9 })

        rival.applyOpacity(0.45)
        XCTAssertEqual(materialAlphas(in: live.root), liveBefore)
        let rivalAlphas = materialAlphas(in: rival.root)
        XCTAssertFalse(rivalAlphas.isEmpty)
        XCTAssertTrue(rivalAlphas.allSatisfy { $0 <= 0.46 })
    }

    func testDeterministicPhaseSamplingIsStableAcrossSeeks() async throws {
        guard let template = await ReplayAthleteLibrary.shared.athleteTemplate() else {
            return XCTFail("Expected V4 athlete template")
        }
        let instance = try XCTUnwrap(template.makeInstance(name: "seek", opacity: 1))
        let adapter = ReplayAthletePoseAdapter(contract: template.contract)

        let sample = ReplayAthleteMotionSample(phase: 1.5, cycleFrac: 0.3, driveFrac: 0.4)
        let fraction = adapter.clipFraction(sport: .rower, sample: sample)
        adapter.apply(sample: sample, sport: .rower, to: instance)
        adapter.apply(sample: sample, sport: .rower, to: instance)
        XCTAssertEqual(fraction, adapter.clipFraction(sport: .rower, sample: sample))
        XCTAssertTrue(instance.hasFiniteJointTransforms())
    }

    func testBundledPackageRequiresAthleteAndSelectsProceduralWhenMissing() async {
        // A valid library load includes the athlete template.
        let set = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        XCTAssertNotNil(set)
        XCTAssertNotNil(set?.athleteTemplate)

        // Low quality always selects procedural regardless of package validity.
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .low, assetSetIsValid: true),
            .procedural
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .medium, assetSetIsValid: true),
            .bundled
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .medium, assetSetIsValid: false),
            .procedural
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .high, assetSetIsValid: false),
            .procedural
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .ultra, assetSetIsValid: true),
            .bundled
        )
    }

    func testProceduralFootRemainsAtAnklePivot() {
        let athlete = ReplayAthleteRig()
        let parent = Entity()
        athlete.build(into: parent, seated: true, accent: .green, opacity: 1, visualProvider: nil)
        // Foot is a child of shin at the ankle: local offset is shin length.
        XCTAssertEqual(athlete.footL.position.y, -0.40, accuracy: 0.0001)
        XCTAssertEqual(athlete.footR.position.y, -0.40, accuracy: 0.0001)
        XCTAssertEqual(athlete.footL.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(athlete.shinL.position.y, -0.42, accuracy: 0.0001)
    }

    func testNativeGeneratorDoesNotDefineHumanAnatomy() throws {
        let generator = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/generate_replay_assets.py")
        let source = try String(contentsOf: generator, encoding: .utf8)
        XCTAssertFalse(source.contains("def athlete_nodes"))
        XCTAssertFalse(source.contains("visual-pelvis"))
        XCTAssertFalse(source.contains("\"skin\""))
        XCTAssertTrue(source.contains("rower_equipment_nodes"))
        XCTAssertTrue(source.contains("skierg_equipment_nodes"))
        XCTAssertTrue(source.contains("bike_equipment_nodes"))
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
