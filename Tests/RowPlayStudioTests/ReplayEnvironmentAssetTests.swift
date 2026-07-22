import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayEnvironmentAssetTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
        ReplayAssetLibrary.shared.resetCacheForTesting()
    }

    func testEveryQualityUsesCompleteProceduralSceneWhileV4ClipGateRejects() async {
        for sport in ReplayAssetCatalog.supportedSports {
            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNil(assetSet)

            for quality in ReplayRenderQuality.allCases {
                let scene = Replay3DSceneBuilder.buildScene(
                    sport: sport,
                    colorScheme: .dark,
                    configuration: quality.configuration,
                    effectiveQuality: quality,
                    bundledAssetSet: assetSet
                )
                XCTAssertEqual(scene.visualSource, .procedural)
                XCTAssertNil(scene.bundledEnvironment)
                XCTAssertTrue(scene.groundEntity.isEnabled)
                XCTAssertNil(scene.root.replayDescendant(named: "bundled-environment"))
            }
        }
    }

    func testGeneratedEnvironmentResourcesLoadAndProduceIndependentClones() async throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let resource = ReplayAssetCatalog.environmentResource(for: sport)
            let url = try XCTUnwrap(ReplayAssetLibrary.bundledResourceURL(for: resource))
            let template = try await Entity(contentsOf: url)
            let first = template.clone(recursive: true)
            let second = template.clone(recursive: true)

            XCTAssertFalse(first === second)
            XCTAssertNotNil(first.replayDescendant(
                named: ReplayAssetCatalog.bundledPrimName(for: "environment-root")
            ))
            XCTAssertNotNil(first.replayDescendant(
                named: ReplayAssetCatalog.bundledPrimName(for: "environment-ground")
            ))
            XCTAssertNotNil(first.replayDescendant(
                named: ReplayAssetCatalog.bundledPrimName(for: "environment-props")
            ))

            first.isEnabled = true
            first.position = SIMD3(3, 0, 0)
            XCTAssertTrue(first.isEnabled)
            XCTAssertNotEqual(first.position.x, second.position.x)
        }
    }

    func testQualityPolicyWouldUseBundledEnvironmentOnlyForACompleteFutureSet() {
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .low, assetSetIsValid: true),
            .procedural
        )
        for quality in [ReplayRenderQuality.medium, .high, .ultra] {
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, assetSetIsValid: true),
                .bundled
            )
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, assetSetIsValid: false),
                .procedural
            )
        }
    }
}
