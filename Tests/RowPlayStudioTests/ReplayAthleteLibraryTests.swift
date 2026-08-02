import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAthleteLibraryTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
    }

    func testProductionAthleteTemplateLoadsFromReferenceBundle() async throws {
        let template = await ReplayAthleteLibrary.shared.athleteTemplate()
        let loaded = try XCTUnwrap(
            template,
            "The bundled production athlete must activate — fallback is for failures only"
        )
        XCTAssertEqual(loaded.contract.semanticBones.count, 19)
        XCTAssertEqual(loaded.contract.helpers.count, 32)
        XCTAssertEqual(loaded.contract.totalBoneCount, 51)
        XCTAssertEqual(loaded.motionTable.boneNames, loaded.contract.semanticBoneNames)
        XCTAssertGreaterThanOrEqual(loaded.motionTable.samplesPerSport, 257)
        // Every contract bone resolves to a distinct loaded skeleton joint.
        XCTAssertEqual(Set(loaded.semanticJointIndices).count, 19)
        XCTAssertEqual(Set(loaded.helperJointIndices).count, 32)
        XCTAssertTrue(
            Set(loaded.semanticJointIndices).isDisjoint(with: Set(loaded.helperJointIndices))
        )
    }

    func testInstancesDriveDeterministicFinitePosesForAllSports() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        for sport in ReplayAssetCatalog.supportedSports {
            let instance = try XCTUnwrap(
                template.makeInstance(sport: sport, name: "live", isRival: false),
                "\(sport.rawValue) instance must build"
            )
            // Direct and shuffled seeks must be deterministic: the same
            // fraction always reproduces the same pose regardless of the
            // seek order that preceded it.
            instance.seek(toClipFraction: 0.25)
            let first = try XCTUnwrap(instance.currentConstraintPose())
            instance.seek(toClipFraction: 0.8)
            instance.seek(toClipFraction: 0.1)
            instance.seek(toClipFraction: 0.25)
            let second = try XCTUnwrap(instance.currentConstraintPose())
            XCTAssertEqual(first.jointTransforms.count, second.jointTransforms.count)
            for index in 0..<first.jointTransforms.count {
                let a = first.jointTransforms[index]
                let b = second.jointTransforms[index]
                XCTAssertEqual(a.translation.x, b.translation.x, accuracy: 1e-6)
                XCTAssertEqual(a.translation.y, b.translation.y, accuracy: 1e-6)
                XCTAssertEqual(a.translation.z, b.translation.z, accuracy: 1e-6)
            }
            // Dense cycle stays finite.
            for step in 0..<64 {
                instance.seek(toClipFraction: Double(step) / 64)
                XCTAssertTrue(
                    instance.hasFiniteJointTransforms(),
                    "\(sport.rawValue) non-finite at step \(step)"
                )
            }
        }
    }

    func testAuthoredMotionActuallyMovesTheSkeleton() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let instance = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "live", isRival: false)
        )
        instance.seek(toClipFraction: 0)
        let catchPose = try XCTUnwrap(instance.currentConstraintPose())
        instance.seek(toClipFraction: 0.38)
        let finishPose = try XCTUnwrap(instance.currentConstraintPose())
        // The hips travel with the slide between catch and finish; a static
        // skeleton means the motion table is not driving the joints.
        var maximumDelta: Float = 0
        for index in 0..<catchPose.jointTransforms.count {
            let delta = simd_distance(
                catchPose.jointTransforms[index].translation,
                finishPose.jointTransforms[index].translation
            )
            maximumDelta = max(maximumDelta, delta)
        }
        XCTAssertGreaterThan(
            maximumDelta,
            0.05,
            "catch → finish should move at least one joint by centimetres"
        )
    }

    func testLiveAndRivalInstancesRemainIndependent() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let live = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "live", isRival: false)
        )
        let rival = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "rival", isRival: true)
        )
        live.seek(toClipFraction: 0.1)
        rival.seek(toClipFraction: 0.6)
        let livePose = try XCTUnwrap(live.currentConstraintPose())
        let rivalPose = try XCTUnwrap(rival.currentConstraintPose())
        var differs = false
        for index in 0..<livePose.jointTransforms.count {
            if simd_distance(
                livePose.jointTransforms[index].translation,
                rivalPose.jointTransforms[index].translation
            ) > 1e-4 {
                differs = true
                break
            }
        }
        XCTAssertTrue(differs, "live and rival skeleton state must be independent")
    }

}
