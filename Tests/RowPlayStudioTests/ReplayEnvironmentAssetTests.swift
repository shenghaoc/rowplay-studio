import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayEnvironmentAssetTests: XCTestCase {
    func testLowQualityKeepsTheCompleteProceduralSceneEvenWhenAssetsAreAvailable() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }

        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.low.configuration,
            effectiveQuality: .low,
            bundledAssetSet: assetSet
        )

        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertNil(scene.bundledEnvironment)
        XCTAssertTrue(scene.groundEntity.isEnabled)
        XCTAssertNil(scene.root.replayDescendant(named: "bundled-environment"))
    }

    func testMediumQualityInstallsMatchingBundledEnvironmentAndSuppressesProceduralGround() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }

        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.medium.configuration,
            effectiveQuality: .medium,
            bundledAssetSet: assetSet
        )

        XCTAssertEqual(scene.visualSource, .bundled)
        XCTAssertFalse(scene.groundEntity.isEnabled)
        guard let environment = scene.bundledEnvironment else {
            return XCTFail("Expected a bundled environment at medium quality")
        }
        XCTAssertTrue(environment.isEnabled)
        XCTAssertEqual(environment.name, "bundled-environment")
        for logicalName in ReplayAssetCatalog.environmentNodeNames {
            XCTAssertNotNil(
                environment.replayDescendant(
                    named: ReplayAssetCatalog.bundledPrimName(for: logicalName)
                ),
                "Bundled environment missing \(logicalName) after clone"
            )
        }
        // Contract identity must survive the scene wrapper rename.
        XCTAssertNotNil(
            environment.replayDescendant(
                named: ReplayAssetCatalog.bundledPrimName(for: "environment-root")
            )
        )
    }

    func testMediumBundledSceneFadesGhostEquipmentAndAthlete() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.medium.configuration,
            effectiveQuality: .medium,
            bundledAssetSet: assetSet
        )
        XCTAssertEqual(scene.visualSource, .bundled)

        func alphas(in entity: Entity) -> [Float] {
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
                values.append(contentsOf: alphas(in: child))
            }
            return values
        }

        let ghostAlphas = alphas(in: scene.ghostRig.root)
        XCTAssertFalse(ghostAlphas.isEmpty)
        XCTAssertTrue(
            ghostAlphas.allSatisfy { $0 <= 0.46 },
            "Bundled ghost equipment and athlete must be translucent"
        )
    }

    func testMediumQualityFallsBackAtomicallyWhenNoValidSetWasLoaded() {
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .bike,
            colorScheme: .light,
            configuration: ReplayRenderQuality.medium.configuration,
            effectiveQuality: .medium,
            bundledAssetSet: nil
        )

        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertNil(scene.bundledEnvironment)
        XCTAssertTrue(scene.groundEntity.isEnabled)
        XCTAssertNotNil(scene.root.replayDescendant(named: "bikeerg-rig"))
    }

    func testMediumQualityRejectsAStaleAssetSetForAnotherSportAtomically() async {
        guard let rowerSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }

        let scene = Replay3DSceneBuilder.buildScene(
            sport: .skierg,
            colorScheme: .light,
            configuration: ReplayRenderQuality.medium.configuration,
            effectiveQuality: .medium,
            bundledAssetSet: rowerSet
        )

        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertNil(scene.bundledEnvironment)
        XCTAssertTrue(scene.groundEntity.isEnabled)
        XCTAssertNotNil(scene.root.replayDescendant(named: "skierg-rig"))
        XCTAssertNil(scene.root.replayDescendant(named: "bundled-environment"))
    }

    func testEnvironmentInstallerReturnsIndependentEnabledClones() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .skierg) else {
            return XCTFail("Expected bundled SkiErg asset set")
        }

        let firstRoot = Entity()
        let first = ReplayEnvironmentAssetInstaller.install(assetSet: assetSet, into: firstRoot)
        let secondRoot = Entity()
        let second = ReplayEnvironmentAssetInstaller.install(assetSet: assetSet, into: secondRoot)

        XCTAssertFalse(first === second)
        XCTAssertTrue(first.isEnabled)
        XCTAssertTrue(second.isEnabled)
        first.position = SIMD3(3, 0, 0)
        XCTAssertNotEqual(first.position.x, second.position.x)
        XCTAssertTrue(firstRoot.children.contains { $0 === first })
        XCTAssertTrue(secondRoot.children.contains { $0 === second })
    }
}
