import Darwin
import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAssetLibraryTests: XCTestCase {
    func testCommittedEquipmentPackagesLoadAtomicallyForEverySport() async throws {
        let library = ReplayAssetLibrary.shared
        library.resetCacheForTesting()

        for sport in ReplayAssetCatalog.supportedSports {
            guard let set = await library.bundledAssetSet(for: sport) else {
                return XCTFail("Expected validated equipment for \(sport.rawValue)")
            }
            XCTAssertEqual(set.sport, sport)
            XCTAssertTrue(set.rigVisualProvider.usesBundledAssets)
            let contractURL = try XCTUnwrap(
                ReplayBundledResourceSupport.bundledURL(
                    name: ReplayEquipmentPackageResource(sport: sport).contractName,
                    extension: ReplayEquipmentPackageResource(sport: sport).contractExtension,
                    subdirectory: ReplayAssetCatalog.equipmentSubdirectory
                )
            )
            let contract = try parsedContract(
                data: Data(contentsOf: contractURL),
                sport: sport
            )
            let required = try requiredVisuals(in: contract)
            XCTAssertEqual(
                set.rigVisualProvider.validatedSourceNames,
                Set(required.map(\.sourceName))
            )
            for sourceName in required.map(\.sourceName) {
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
            manifest: try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: ReplayAssetCatalog.equipmentManifestName,
                extension: ReplayAssetCatalog.equipmentManifestExtension,
                subdirectory: ReplayAssetCatalog.equipmentSubdirectory
            ))
        )
        var reports: [(Sport, ReplayAssetLoadFailure)] = []
        let library = ReplayAssetLibrary(source: source, failureReporter: { sport, failure in
            reports.append((sport, failure))
        })

        let first = await library.bundledAssetSet(for: .rower)
        let second = await library.bundledAssetSet(for: .rower)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(source.packageRequests, 1)
        XCTAssertEqual(source.contractRequests, 0)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.0, .rower)
        XCTAssertEqual(reports.first?.1, .packageMissing)
        XCTAssertEqual(library.lastFailures[.rower], .packageMissing)
    }

    func testHashMismatchRejectsWholeEquipmentSet() async throws {
        let sport = Sport.bike
        let resource = ReplayEquipmentPackageResource(sport: sport)
        let manifest = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
            name: ReplayAssetCatalog.equipmentManifestName,
            extension: ReplayAssetCatalog.equipmentManifestExtension,
            subdirectory: ReplayAssetCatalog.equipmentSubdirectory
        ))
        let package = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
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

        let set = await library.bundledAssetSet(for: sport)
        XCTAssertNil(set)
        XCTAssertEqual(library.lastFailures[sport], .contractHashMismatch)
    }

    func testConcurrentRequestsShareOnePackageLoad() async throws {
        let sport = Sport.rower
        let resource = ReplayEquipmentPackageResource(sport: sport)
        let source = TestEquipmentResourceSource(
            manifest: try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: ReplayAssetCatalog.equipmentManifestName,
                extension: ReplayAssetCatalog.equipmentManifestExtension,
                subdirectory: ReplayAssetCatalog.equipmentSubdirectory
            )),
            packages: [sport: try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: resource.packageName,
                extension: resource.packageExtension,
                subdirectory: resource.subdirectory
            ))],
            contracts: [sport: try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: resource.contractName,
                extension: resource.contractExtension,
                subdirectory: resource.subdirectory
            ))]
        )
        let library = ReplayAssetLibrary(source: source)

        async let first = library.bundledAssetSet(for: sport)
        async let second = library.bundledAssetSet(for: sport)
        let results = await (first, second)

        XCTAssertNotNil(results.0)
        XCTAssertNotNil(results.1)
        XCTAssertEqual(source.packageRequests, 1)
        XCTAssertEqual(source.contractRequests, 1)
    }

    func testConcurrentDifferentSportsShareOneManifestPreflight() async throws {
        let sports: [Sport] = [.rower, .bike]
        var packages: [Sport: URL] = [:]
        var contracts: [Sport: URL] = [:]
        for sport in sports {
            let resource = ReplayEquipmentPackageResource(sport: sport)
            packages[sport] = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: resource.packageName,
                extension: resource.packageExtension,
                subdirectory: resource.subdirectory
            ))
            contracts[sport] = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: resource.contractName,
                extension: resource.contractExtension,
                subdirectory: resource.subdirectory
            ))
        }
        let source = TestEquipmentResourceSource(
            manifest: try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: ReplayAssetCatalog.equipmentManifestName,
                extension: ReplayAssetCatalog.equipmentManifestExtension,
                subdirectory: ReplayAssetCatalog.equipmentSubdirectory
            )),
            packages: packages,
            contracts: contracts
        )
        let library = ReplayAssetLibrary(source: source)

        async let rower = library.bundledAssetSet(for: .rower)
        async let bike = library.bundledAssetSet(for: .bike)
        let results = await (rower, bike)

        XCTAssertNotNil(results.0)
        XCTAssertNotNil(results.1)
        XCTAssertEqual(source.manifestRequests, 1)
        XCTAssertEqual(source.packageRequests, 2)
        XCTAssertEqual(source.contractRequests, 2)
    }

    func testPortablePreflightValidatesCommittedPackageOffMainThread() async throws {
        let sport = Sport.rower
        let resource = ReplayEquipmentPackageResource(sport: sport)
        let manifestURL = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
            name: ReplayAssetCatalog.equipmentManifestName,
            extension: ReplayAssetCatalog.equipmentManifestExtension,
            subdirectory: ReplayAssetCatalog.equipmentSubdirectory
        ))
        let packageURL = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
            name: resource.packageName,
            extension: resource.packageExtension,
            subdirectory: resource.subdirectory
        ))
        let contractURL = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
            name: resource.contractName,
            extension: resource.contractExtension,
            subdirectory: resource.subdirectory
        ))

        let outcome = await Task.detached(priority: .userInitiated) {
            let manifestResult = ReplayEquipmentPortablePreflight.loadManifest(
                contentsOf: manifestURL
            )
            guard case .success(let manifest) = manifestResult,
                  let expected = manifest[sport] else {
                return (pthread_main_np() != 0, false)
            }
            let packageResult = ReplayEquipmentPortablePreflight.validatePackage(
                packageURL: packageURL,
                contractURL: contractURL,
                expected: expected,
                sport: sport
            )
            guard case .success(let contract) = packageResult else {
                return (pthread_main_np() != 0, false)
            }
            return (pthread_main_np() != 0, contract.sport == sport)
        }.value

        XCTAssertFalse(outcome.0, "Portable I/O and validation must not occupy the main thread")
        XCTAssertTrue(outcome.1)
    }

    func testStreamingPackageHashMatchesInMemoryHash() throws {
        let resource = ReplayEquipmentPackageResource(sport: .rower)
        let url = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
            name: resource.packageName,
            extension: resource.packageExtension,
            subdirectory: resource.subdirectory
        ))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(
            try ReplayBundledResourceSupport.sha256Hex(contentsOf: url),
            ReplayBundledResourceSupport.sha256Hex(of: data)
        )
    }

    private func parsedContract(
        data: Data,
        sport: Sport
    ) throws -> ReplayEquipmentPackageContract {
        switch ReplayAssetCatalog.parsePackageContract(data: data, sport: sport) {
        case .success(let contract):
            contract
        case .failure(let failure):
            throw failure
        }
    }

    private func requiredVisuals(
        in contract: ReplayEquipmentPackageContract
    ) throws -> [ReplayEquipmentRequiredVisualSpec] {
        switch ReplayAssetCatalog.requiredVisuals(in: contract) {
        case .success(let visuals):
            visuals
        case .failure(let failure):
            throw failure
        }
    }
}

@MainActor
private final class TestEquipmentResourceSource: ReplayAssetResourceSource {
    let manifest: URL
    let packages: [Sport: URL]
    let contracts: [Sport: URL]
    private(set) var packageRequests = 0
    private(set) var contractRequests = 0
    private(set) var manifestRequests = 0

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

    func manifestURL() -> URL? {
        manifestRequests += 1
        return manifest
    }
}
