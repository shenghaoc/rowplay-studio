import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAssetLibraryTests: XCTestCase {
    func testCommittedEquipmentPackagesLoadAtomicallyForEverySport() async {
        let library = ReplayAssetLibrary.shared
        library.resetCacheForTesting()

        for sport in ReplayAssetCatalog.supportedSports {
            guard let set = await library.bundledEquipmentSet(for: sport) else {
                return XCTFail("Expected validated equipment for \(sport.rawValue)")
            }
            XCTAssertEqual(set.sport, sport)
            XCTAssertTrue(set.rigVisualProvider.usesBundledAssets)
            let required = ReplayAssetCatalog.requiredCompositeSourceNames(for: sport)
                + ReplayAssetCatalog.requiredLeafSourceNames(for: sport)
            for sourceName in required {
                let first = set.rigVisualProvider.cloneVisual(named: sourceName)
                let second = set.rigVisualProvider.cloneVisual(named: sourceName)
                XCTAssertNotNil(first, "Missing \(sourceName)")
                XCTAssertNotNil(second, "Missing second clone for \(sourceName)")
                XCTAssertFalse(first === second)
            }
        }
    }

    func testMissingPackageCachesCompleteFallback() async throws {
        let source = TestEquipmentResourceSource(
            manifest: try XCTUnwrap(ReplayAssetLibrary.bundledURL(
                name: ReplayAssetCatalog.equipmentManifestName,
                extension: ReplayAssetCatalog.equipmentManifestExtension,
                subdirectory: ReplayAssetCatalog.equipmentSubdirectory
            ))
        )
        let library = ReplayAssetLibrary(source: source)

        let first = await library.bundledEquipmentSet(for: .rower)
        let second = await library.bundledEquipmentSet(for: .rower)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(source.packageRequests, 1)
        XCTAssertEqual(source.contractRequests, 0)
    }

    func testHashMismatchRejectsWholeEquipmentSet() async throws {
        let sport = Sport.bike
        let resource = ReplayEquipmentPackageResource(sport: sport)
        let manifest = try XCTUnwrap(ReplayAssetLibrary.bundledURL(
            name: ReplayAssetCatalog.equipmentManifestName,
            extension: ReplayAssetCatalog.equipmentManifestExtension,
            subdirectory: ReplayAssetCatalog.equipmentSubdirectory
        ))
        let package = try XCTUnwrap(ReplayAssetLibrary.bundledURL(
            name: resource.packageName,
            extension: resource.packageExtension,
            subdirectory: resource.subdirectory
        ))
        let source = TestEquipmentResourceSource(
            manifest: manifest,
            packages: [sport: package],
            contracts: [sport: package]
        )
        let library = ReplayAssetLibrary(source: source)

        let set = await library.bundledEquipmentSet(for: sport)
        XCTAssertNil(set)
    }
}

@MainActor
private final class TestEquipmentResourceSource: ReplayAssetResourceSource {
    let manifest: URL
    let packages: [Sport: URL]
    let contracts: [Sport: URL]
    private(set) var packageRequests = 0
    private(set) var contractRequests = 0

    init(
        manifest: URL,
        packages: [Sport: URL] = [:],
        contracts: [Sport: URL] = [:]
    ) {
        self.manifest = manifest
        self.packages = packages
        self.contracts = contracts
    }

    func packageURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        packageRequests += 1
        return packages[resource.sport]
    }

    func contractURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        contractRequests += 1
        return contracts[resource.sport]
    }

    func manifestURL() -> URL? { manifest }
}
