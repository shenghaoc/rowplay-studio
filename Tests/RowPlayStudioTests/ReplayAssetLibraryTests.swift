import Foundation
import RealityKit
import RowPlayCore
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAssetLibraryTests: XCTestCase {
    func testBundledEquipmentResourcesLoadWhileStrictV4GateRejectsCompleteSets() async {
        for sport in ReplayAssetCatalog.supportedSports {
            for resource in ReplayAssetCatalog.resources(for: sport) {
                guard let url = ReplayAssetLibrary.bundledResourceURL(for: resource) else {
                    return XCTFail("Expected bundled URL for \(resource.relativePath)")
                }
                do {
                    let root = try await Entity(contentsOf: url)
                    XCTAssertFalse(
                        root.children.isEmpty,
                        "Expected RealityKit content in \(resource.relativePath)"
                    )
                    for logicalName in ReplayAssetCatalog.requiredNodeNames(for: resource) {
                        XCTAssertNotNil(
                            root.replayDescendant(
                                named: ReplayAssetCatalog.bundledPrimName(for: logicalName)
                            ),
                            "Expected \(logicalName) in \(resource.relativePath)"
                        )
                    }
                } catch {
                    XCTFail(
                        "RealityKit could not load \(resource.relativePath): \(error)"
                    )
                }
            }

            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNil(
                assetSet,
                "The actual merged V4 clip mismatch must reject the complete \(sport.rawValue) set"
            )
        }
    }

    func testEquipmentTemplatesProduceIndependentRigAndEnvironmentClones() async throws {
        let rig = ReplayAssetCatalog.rigResource(for: .rower)
        let environment = ReplayAssetCatalog.environmentResource(for: .rower)
        let rigRoot = try await Entity(contentsOf: try XCTUnwrap(
            ReplayAssetLibrary.bundledResourceURL(for: rig)
        ))
        let provider = try XCTUnwrap(ReplayBundledRigVisualProvider(
            root: rigRoot,
            requiredNodeNames: Set(ReplayAssetCatalog.requiredRigNodeNames(for: .rower))
        ))

        guard let visualName = ReplayAssetCatalog.requiredRigNodeNames(for: .rower).first,
              let firstVisual = provider.cloneVisual(named: visualName),
              let secondVisual = provider.cloneVisual(named: visualName) else {
            return XCTFail("Expected the complete rower equipment visual contract")
        }

        XCTAssertFalse(firstVisual === secondVisual)
        firstVisual.position = SIMD3(4, 5, 6)
        XCTAssertNotEqual(firstVisual.position.x, secondVisual.position.x)
        XCTAssertEqual(secondVisual.name, visualName)

        let environmentRoot = try await Entity(contentsOf: try XCTUnwrap(
            ReplayAssetLibrary.bundledResourceURL(for: environment)
        ))
        let firstEnvironment = environmentRoot.clone(recursive: true)
        let secondEnvironment = environmentRoot.clone(recursive: true)
        XCTAssertFalse(firstEnvironment === secondEnvironment)
        XCTAssertNotNil(firstEnvironment.replayDescendant(
            named: ReplayAssetCatalog.bundledPrimName(for: "environment-ground")
        ))

        firstEnvironment.position.x = 7
        XCTAssertNotEqual(firstEnvironment.position.x, secondEnvironment.position.x)
    }

    func testMissingInjectedResourceFallsBackWithoutConstructingPartialSet() async throws {
        let rig = ReplayAssetCatalog.rigResource(for: .rower)
        let rigURL = try XCTUnwrap(ReplayAssetLibrary.bundledResourceURL(for: rig))
        let source = TestResourceSource(urls: [rig: rigURL])
        let library = ReplayAssetLibrary(source: source)

        let firstAttempt = await library.bundledAssetSet(for: .rower)
        XCTAssertNil(firstAttempt)
        XCTAssertEqual(source.requestedResources, [rig, ReplayAssetCatalog.environmentResource(for: .rower)])
        // A cached failed set must remain a complete fallback, not retry into a
        // partially loaded rig on a subsequent scene update.
        let secondAttempt = await library.bundledAssetSet(for: .rower)
        XCTAssertNil(secondAttempt)
    }

    func testMalformedInjectedResourceFallsBackToProcedural() async throws {
        let rig = ReplayAssetCatalog.rigResource(for: .skierg)
        let environment = ReplayAssetCatalog.environmentResource(for: .skierg)
        let environmentURL = try XCTUnwrap(
            ReplayAssetLibrary.bundledResourceURL(for: environment)
        )
        let malformedURL = try makeTemporaryFile(
            named: "malformed-rig.usda",
            data: Data([0xFF, 0xFE, 0x00])
        )
        defer { removeTemporaryDirectory(containing: malformedURL) }

        let source = TestResourceSource(urls: [
            rig: malformedURL,
            environment: environmentURL,
        ])
        let library = ReplayAssetLibrary(source: source)

        let assetSet = await library.bundledAssetSet(for: .skierg)
        XCTAssertNil(assetSet)
        XCTAssertEqual(source.requestedResources, [rig])
    }

    func testIncompleteInjectedContractFallsBackAtomically() async throws {
        let sport = Sport.bike
        let rig = ReplayAssetCatalog.rigResource(for: sport)
        let environment = ReplayAssetCatalog.environmentResource(for: sport)
        let incompleteNames = ReplayAssetCatalog.requiredNodeNames(for: rig)
            .filter { $0 != "visual-pedal-R" }
        let incompleteRigURL = try makeTemporaryFile(
            named: "incomplete-rig.usda",
            data: Data(incompleteRigSource(with: incompleteNames).utf8)
        )
        defer { removeTemporaryDirectory(containing: incompleteRigURL) }

        let environmentURL = try XCTUnwrap(
            ReplayAssetLibrary.bundledResourceURL(for: environment)
        )
        let source = TestResourceSource(urls: [
            rig: incompleteRigURL,
            environment: environmentURL,
        ])
        let library = ReplayAssetLibrary(source: source)

        let assetSet = await library.bundledAssetSet(for: sport)
        XCTAssertNil(assetSet)
        XCTAssertEqual(source.requestedResources, [rig, environment])
    }

    func testEmptyRequiredVisualGeometryFallsBackAtomically() async throws {
        let sport = Sport.bike
        let rig = ReplayAssetCatalog.rigResource(for: sport)
        let environment = ReplayAssetCatalog.environmentResource(for: sport)
        let originalURL = try XCTUnwrap(ReplayAssetLibrary.bundledResourceURL(for: rig))
        var sourceText = try String(contentsOf: originalURL, encoding: .utf8)
        let marker = "custom string rowplay:logicalName = \"visual-pedal-R\""
        let markerRange = try XCTUnwrap(sourceText.range(of: marker))
        let nextNode = sourceText.range(
            of: "custom string rowplay:logicalName",
            range: markerRange.upperBound..<sourceText.endIndex
        )?.lowerBound ?? sourceText.endIndex
        let pedalBlockRange = markerRange.lowerBound..<nextNode
        let emptyPedalBlock = sourceText[pedalBlockRange].replacingOccurrences(
            of: "point3f[] points",
            with: "point3f[] emptyPoints"
        )
        sourceText.replaceSubrange(pedalBlockRange, with: emptyPedalBlock)
        let emptyRigURL = try makeTemporaryFile(
            named: "empty-required-visual.usda",
            data: Data(sourceText.utf8)
        )
        defer { removeTemporaryDirectory(containing: emptyRigURL) }

        let inspection = try XCTUnwrap(ReplayAssetLibrary.inspect(resource: rig, at: emptyRigURL))
        XCTAssertFalse(inspection.geometryNodeNames.contains("visual-pedal-R"))
        let environmentURL = try XCTUnwrap(ReplayAssetLibrary.bundledResourceURL(for: environment))
        let environmentInspection = try XCTUnwrap(
            ReplayAssetLibrary.inspect(resource: environment, at: environmentURL)
        )
        let validation = ReplayAssetCatalog.validateAssetSet(
            for: sport,
            inspections: [inspection, environmentInspection]
        )
        XCTAssertTrue(validation.failures.contains(
            .missingRequiredNodeGeometry(resource: rig, name: "visual-pedal-R")
        ))

        let source = TestResourceSource(urls: [
            rig: emptyRigURL,
            environment: environmentURL,
        ])
        let library = ReplayAssetLibrary(source: source)
        let assetSet = await library.bundledAssetSet(for: sport)
        XCTAssertNil(assetSet)
        XCTAssertEqual(source.requestedResources, [rig, environment])
    }

    private func incompleteRigSource(with nodeNames: [String]) -> String {
        let prims = nodeNames.map { name in
            """
            def Mesh \"\(ReplayAssetCatalog.bundledPrimName(for: name))\"
            {
                custom string rowplay:logicalName = \"\(name)\"
            }
            """
        }.joined(separator: "\n")
        return """
        #usda 1.0
        # rowplay-triangles: 1
        \(prims)
        """
    }

    private func makeTemporaryFile(named name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RowPlayStudioReplayAssetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func removeTemporaryDirectory(containing url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@MainActor
private final class TestResourceSource: ReplayAssetResourceSource {
    private let urls: [ReplayAssetResource: URL]
    private(set) var requestedResources: [ReplayAssetResource] = []

    init(urls: [ReplayAssetResource: URL]) {
        self.urls = urls
    }

    func url(for resource: ReplayAssetResource) -> URL? {
        requestedResources.append(resource)
        return urls[resource]
    }
}
