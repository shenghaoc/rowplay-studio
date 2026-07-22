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

    func testMergedAssetIsAtomicallyRejectedWhenItDoesNotProvideContractClipNames() async throws {
        let contract = try loadContract()
        let manifest = try loadSourceManifest()
        let root = try await Entity(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.usdzResourceName,
            ext: ReplayAthleteCatalog.usdzExtension
        ))

        let requiredNames = Set(ReplayAssetCatalog.supportedSports.map {
            ReplayAthleteCatalog.expectedClipName(for: $0)
        })
        let availableNames = Set(root.availableAnimations.compactMap(\.name))

        // The final merged source has a row-cycle animation under an
        // underscore name and no contract-named Ski/Bike clips. Do not accept
        // an arbitrary first animation or a lossy alias: that would animate
        // the wrong sport while appearing to succeed.
        XCTAssertTrue(
            requiredNames.isDisjoint(with: availableNames),
            "The exact merged artifact unexpectedly gained contract clip names; update the V4 gate."
        )
        XCTAssertNil(ReplayAthleteTemplate(
            root: root,
            contract: contract,
            sourceManifest: manifest
        ))

        let athlete = await ReplayAthleteLibrary.shared.athleteTemplate()
        XCTAssertNil(athlete)
        for sport in ReplayAssetCatalog.supportedSports {
            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNil(assetSet, "A missing required V4 clip must reject the complete \(sport.rawValue) set")
        }
    }

    func testQualitySelectionUsesCompleteProceduralFallbackWhenV4IsRejected() async {
        for sport in ReplayAssetCatalog.supportedSports {
            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNil(assetSet)
        }

        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .low, assetSetIsValid: true),
            .procedural
        )
        for quality in [ReplayRenderQuality.medium, .high, .ultra] {
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, assetSetIsValid: false),
                .procedural
            )
        }
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

    private func loadContract() throws -> ReplayAthleteContract {
        let data = try Data(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.contractResourceName,
            ext: ReplayAthleteCatalog.contractExtension
        ))
        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: data) else {
            throw ReplayTestError.invalidContract
        }
        return contract
    }

    private func loadSourceManifest() throws -> ReplayAthleteSourceManifest {
        let data = try Data(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            ext: ReplayAthleteCatalog.sourceManifestExtension
        ))
        guard case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: data) else {
            throw ReplayTestError.invalidManifest
        }
        return manifest
    }

    private func resourceURL(name: String, ext: String) throws -> URL {
        // Resolve the exact committed resource for the source-artifact gate.
        // Production loading is separately exercised through Bundle.module by
        // ReplayAthleteLibrary / ReplayAssetLibrary above.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RowPlayStudio/Resources/Replay3D/\(name).\(ext)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReplayTestError.missingResource
        }
        return url
    }
}

private enum ReplayTestError: Error {
    case invalidContract
    case invalidManifest
    case missingResource
}
