import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

final class ReplayAssetCatalogTests: XCTestCase {
    func testCatalogListsAllSixBundledResourcesInDeterministicOrder() {
        XCTAssertEqual(
            ReplayAssetCatalog.resources.map(\.relativePath),
            [
                "Replay3D/rower-rig.usda",
                "Replay3D/rower-environment.usda",
                "Replay3D/skierg-rig.usda",
                "Replay3D/skierg-environment.usda",
                "Replay3D/bike-rig.usda",
                "Replay3D/bike-environment.usda",
            ]
        )
        XCTAssertEqual(
            ReplayAssetCatalog.resourceNames,
            [
                "rower-rig.usda",
                "rower-environment.usda",
                "skierg-rig.usda",
                "skierg-environment.usda",
                "bike-rig.usda",
                "bike-environment.usda",
            ]
        )
    }

    func testCatalogDefinesCompleteNodeContractsForEverySport() {
        for sport in ReplayAssetCatalog.supportedSports {
            let rigNodes = ReplayAssetCatalog.requiredRigNodeNames(for: sport)
            XCTAssertEqual(rigNodes.count, Set(rigNodes).count)
            XCTAssertTrue(rigNodes.starts(with: ReplayAssetCatalog.commonRigNodeNames))

            let environment = ReplayAssetCatalog.environmentResource(for: sport)
            XCTAssertEqual(
                ReplayAssetCatalog.requiredNodeNames(for: environment),
                ["environment-root", "environment-ground", "environment-props"]
            )
        }

        XCTAssertTrue(
            ReplayAssetCatalog.requiredRigNodeNames(for: .rower)
                .contains("visual-oar-starboard")
        )
        XCTAssertTrue(
            ReplayAssetCatalog.requiredRigNodeNames(for: .skierg)
                .contains("visual-cable")
        )
        XCTAssertTrue(
            ReplayAssetCatalog.requiredRigNodeNames(for: .bike)
                .contains("visual-chainRing")
        )
    }

    func testGoldenContractMatchesTheCatalogIncludingBoundsMaterialsAndUSDNames() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "replay-asset-contract", withExtension: "json")
        )
        let data = try Data(contentsOf: fixtureURL)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let entries = try XCTUnwrap(root["resources"] as? [[String: Any]])
        XCTAssertEqual(entries.count, ReplayAssetCatalog.resources.count)

        for resource in ReplayAssetCatalog.resources {
            let entry = try XCTUnwrap(entries.first {
                ($0["name"] as? String) == resource.fileName
            })
            XCTAssertEqual(entry["sport"] as? String, resource.sport.rawValue)
            XCTAssertEqual(entry["kind"] as? String, resource.kind.rawValue)
            XCTAssertEqual(
                entry["requiredNodes"] as? [String],
                ReplayAssetCatalog.requiredNodeNames(for: resource)
            )
            XCTAssertEqual(
                entry["triangleCeiling"] as? Int,
                ReplayAssetCatalog.budget.maximumTriangleCount(for: resource.kind)
            )
            XCTAssertEqual(
                entry["requiredMaterialCategories"] as? [String],
                ReplayAssetCatalog.requiredMaterialCategories(for: resource)
            )

            let primNames = try XCTUnwrap(entry["usdPrimNames"] as? [String: String])
            for logicalName in ReplayAssetCatalog.requiredNodeNames(for: resource) {
                XCTAssertEqual(
                    primNames[logicalName],
                    ReplayAssetCatalog.bundledPrimName(for: logicalName)
                )
            }

            let bounds = try XCTUnwrap(entry["expectedBounds"] as? [String: [Double]])
            let expected = ReplayAssetCatalog.expectedBounds(for: resource)
            XCTAssertEqual(bounds["min"], [expected.minimum.x, expected.minimum.y, expected.minimum.z])
            XCTAssertEqual(bounds["max"], [expected.maximum.x, expected.maximum.y, expected.maximum.z])
        }
    }

    func testCatalogEnforcesPhaseElevenAssetBudgets() {
        XCTAssertEqual(ReplayAssetCatalog.budget.maximumRigTriangleCount, 18_000)
        XCTAssertEqual(ReplayAssetCatalog.budget.maximumEnvironmentTriangleCount, 30_000)
        XCTAssertEqual(
            ReplayAssetCatalog.budget.combinedByteLimitExclusive,
            15 * 1_024 * 1_024
        )
        XCTAssertEqual(
            ReplayAssetCatalog.budget.maximumTriangleCount(for: .rig),
            18_000
        )
        XCTAssertEqual(
            ReplayAssetCatalog.budget.maximumTriangleCount(for: .environment),
            30_000
        )
    }

    func testQualityPolicySelectsBundledAssetsOnlyForAValidMediumOrHigherSet() {
        let valid = ReplayAssetValidationResult()
        let invalid = ReplayAssetValidationResult(failures: [
            .missingResource(ReplayAssetCatalog.rigResource(for: .rower)),
        ])

        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .low, validation: valid),
            .procedural
        )
        for quality in [ReplayRenderQuality.medium, .high, .ultra] {
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, validation: valid),
                .bundled
            )
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, validation: invalid),
                .procedural
            )
        }
    }

    func testPerSportValidationIsAllOrNothing() {
        let sport = Sport.rower
        let validInspections = ReplayAssetCatalog.resources(for: sport).map {
            validInspection($0)
        }
        let validResult = ReplayAssetCatalog.validateAssetSet(
            for: sport,
            inspections: validInspections
        )
        XCTAssertTrue(validResult.isValid)
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .medium, validation: validResult),
            .bundled
        )

        let incompleteResult = ReplayAssetCatalog.validateAssetSet(
            for: sport,
            inspections: [validInspection(ReplayAssetCatalog.rigResource(for: sport))]
        )
        XCTAssertFalse(incompleteResult.isValid)
        XCTAssertTrue(incompleteResult.failures.contains(
            .missingResource(ReplayAssetCatalog.environmentResource(for: sport))
        ))
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .medium, validation: incompleteResult),
            .procedural
        )
    }

    func testValidationRejectsMissingRequiredNodesAndTriangleBudgetViolations() {
        let sport = Sport.bike
        let rig = ReplayAssetCatalog.rigResource(for: sport)
        let environment = ReplayAssetCatalog.environmentResource(for: sport)
        let incompleteRigNodes = ReplayAssetCatalog.requiredNodeNames(for: rig)
            .filter { $0 != "visual-pedal-R" }
        let invalidRig = ReplayAssetInspection(
            resource: rig,
            nodeNames: incompleteRigNodes,
            triangleCount: ReplayAssetCatalog.budget.maximumRigTriangleCount + 1,
            byteCount: 1,
            hasGeometry: true,
            hasFiniteTransforms: true,
            hasFiniteNormals: true,
            hasFiniteBounds: true,
            containsCamera: false,
            containsLight: false
        )

        let result = ReplayAssetCatalog.validateAssetSet(
            for: sport,
            inspections: [invalidRig, validInspection(environment)]
        )

        XCTAssertTrue(result.failures.contains(
            .missingRequiredNode(resource: rig, name: "visual-pedal-R")
        ))
        XCTAssertTrue(result.failures.contains(
            .triangleBudgetExceeded(
                resource: rig,
                actual: ReplayAssetCatalog.budget.maximumRigTriangleCount + 1,
                maximum: ReplayAssetCatalog.budget.maximumRigTriangleCount
            )
        ))
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .ultra, validation: result),
            .procedural
        )
    }

    func testBundleValidationRejectsStrictFifteenMiBLimit() {
        var inspections = ReplayAssetCatalog.resources.map { validInspection($0) }
        let oversizedResource = inspections[0].resource
        inspections[0] = validInspection(
            oversizedResource,
            byteCount: ReplayAssetCatalog.budget.combinedByteLimitExclusive
                - (inspections.count - 1)
        )

        let result = ReplayAssetCatalog.validateBundle(inspections: inspections)
        XCTAssertTrue(result.failures.contains(
            .combinedByteBudgetExceeded(
                actual: ReplayAssetCatalog.budget.combinedByteLimitExclusive,
                limitExclusive: ReplayAssetCatalog.budget.combinedByteLimitExclusive
            )
        ))
    }

    private func validInspection(
        _ resource: ReplayAssetResource,
        byteCount: Int = 1
    ) -> ReplayAssetInspection {
        ReplayAssetInspection(
            resource: resource,
            nodeNames: ReplayAssetCatalog.requiredNodeNames(for: resource),
            triangleCount: 1,
            byteCount: byteCount,
            hasGeometry: true,
            hasFiniteTransforms: true,
            hasFiniteNormals: true,
            hasFiniteBounds: true,
            containsCamera: false,
            containsLight: false
        )
    }
}
