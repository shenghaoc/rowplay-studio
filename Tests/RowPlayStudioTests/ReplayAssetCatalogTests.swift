import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

final class ReplayAssetCatalogTests: XCTestCase {
    func testCatalogRequiresTheSevenCompositeTemplates() {
        XCTAssertEqual(
            ReplayAssetCatalog.requiredCompositeSourceNames(for: .rower),
            [
                "equipment:row:boat-assembly",
                "equipment:row:seat-carriage",
                "equipment:row:oar-rig",
            ]
        )
        XCTAssertEqual(
            ReplayAssetCatalog.requiredCompositeSourceNames(for: .skierg),
            ["equipment:ski:ski-assembly"]
        )
        XCTAssertEqual(
            ReplayAssetCatalog.requiredCompositeSourceNames(for: .bike),
            [
                "equipment:bike:wheel-assembly",
                "equipment:bike:frame-assembly",
                "equipment:bike:drivetrain-assembly",
            ]
        )
        // SkiErg poles are authored as leaves; RowErg keeps the spoon leaf.
        XCTAssertEqual(
            ReplayAssetCatalog.requiredLeafSourceNames(for: .skierg),
            [
                "equipment:ski:pole-shaft",
                "equipment:ski:pole-grip",
                "equipment:ski:pole-basket",
            ]
        )
        XCTAssertEqual(
            ReplayAssetCatalog.requiredLeafSourceNames(for: .rower),
            ["equipment:row:blade"]
        )
        XCTAssertTrue(ReplayAssetCatalog.requiredLeafSourceNames(for: .bike).isEmpty)
    }

    func testCommittedSidecarContractsParseAndValidateForEverySport() throws {
        for sport in ReplayAssetCatalog.supportedSports {
            let resource = ReplayEquipmentPackageResource(sport: sport)
            let url = try committedReferenceURL(
                "equipment/\(resource.contractName).\(resource.contractExtension)"
            )
            let data = try Data(contentsOf: url)
            let contract = try parsedContract(data: data, sport: sport)
            guard case .success = ReplayAssetCatalog.validatePackageContract(contract) else {
                return XCTFail("\(sport.rawValue) sidecar failed validation")
            }
            XCTAssertEqual(contract.sourceCommit.count, 40)
            // Exported prim names must be USD-safe (no colons).
            for node in contract.nodes {
                XCTAssertFalse(node.exportedName.contains(":"))
                for part in node.parts {
                    XCTAssertFalse(part.exportedName.contains(":"))
                }
            }
        }
    }

    func testRequiredPartsMatchThePinnedUpstreamValidator() throws {
        let resource = ReplayEquipmentPackageResource(sport: .rower)
        let url = try committedReferenceURL(
            "equipment/\(resource.contractName).\(resource.contractExtension)"
        )
        let data = try Data(contentsOf: url)
        let contract = try parsedContract(data: data, sport: .rower)
        let boat = try XCTUnwrap(contract.node(sourceName: "equipment:row:boat-assembly"))
        XCTAssertEqual(
            Set(boat.parts.map(\.part)),
            ReplayAssetCatalog.requiredParts["equipment:row:boat-assembly"]
        )
        let oar = try XCTUnwrap(contract.node(sourceName: "equipment:row:oar-rig"))
        XCTAssertTrue(oar.parts.contains { $0.part == "grip" })
        XCTAssertTrue(oar.parts.contains { $0.part == "handle-cap" })
    }

    func testQualityPolicyUsesAuthoredEquipmentAtHighAndUltraOnly() {
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .low, assetSetIsValid: true),
            .procedural
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .medium, assetSetIsValid: true),
            .procedural
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .high, assetSetIsValid: true),
            .bundled
        )
        XCTAssertEqual(
            ReplayAssetCatalog.visualSource(for: .ultra, assetSetIsValid: true),
            .bundled
        )
        for quality in ReplayRenderQuality.allCases {
            XCTAssertEqual(
                ReplayAssetCatalog.visualSource(for: quality, assetSetIsValid: false),
                .procedural,
                "an invalid set must always select the complete procedural fallback"
            )
        }
    }

    func testValidationRejectsMissingAndDuplicatedParts() {
        let intact = ReplayEquipmentPackageContract(
            sport: .skierg,
            sourceCommit: String(repeating: "a", count: 40),
            sourceGlbSha256: String(repeating: "b", count: 64),
            nodes: skiNodes()
        )
        guard case .success = ReplayAssetCatalog.validatePackageContract(intact) else {
            return XCTFail("Intact contract must validate")
        }

        let missingPart = ReplayEquipmentPackageContract(
            sport: .skierg,
            sourceCommit: intact.sourceCommit,
            sourceGlbSha256: intact.sourceGlbSha256,
            nodes: skiNodes(dropPart: "binding-toe")
        )
        XCTAssertEqual(
            failure(from: ReplayAssetCatalog.validatePackageContract(missingPart)),
            .missingPart(node: "equipment:ski:ski-assembly", part: "binding-toe")
        )

        let missingLeaf = ReplayEquipmentPackageContract(
            sport: .skierg,
            sourceCommit: intact.sourceCommit,
            sourceGlbSha256: intact.sourceGlbSha256,
            nodes: skiNodes(dropLeaf: "equipment:ski:pole-basket")
        )
        XCTAssertEqual(
            failure(from: ReplayAssetCatalog.validatePackageContract(missingLeaf)),
            .missingNode(
                sourceName: "equipment:ski:pole-basket",
                expectedKind: "leaf"
            )
        )

        let duplicatedPart = ReplayEquipmentPackageContract(
            sport: .skierg,
            sourceCommit: intact.sourceCommit,
            sourceGlbSha256: intact.sourceGlbSha256,
            nodes: skiNodes(duplicatePart: true)
        )
        let duplicatedID = skiNodes().first?.parts.first?.part
        XCTAssertEqual(
            failure(from: ReplayAssetCatalog.validatePackageContract(duplicatedPart)),
            .duplicatePart(
                node: "equipment:ski:ski-assembly",
                part: try XCTUnwrap(duplicatedID)
            )
        )
    }

    func testPackageParserRejectsSidecarForAnotherSport() throws {
        let resource = ReplayEquipmentPackageResource(sport: .rower)
        let url = try committedReferenceURL(
            "equipment/\(resource.contractName).\(resource.contractExtension)"
        )
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        root["sport"] = "bike"
        let mismatched = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(
            failure(from: ReplayAssetCatalog.parsePackageContract(
                data: mismatched,
                sport: .rower
            )),
            .sportMismatch(expected: .rower, actual: "bike")
        )
    }

    private func skiNodes(
        dropPart: String? = nil,
        dropLeaf: String? = nil,
        duplicatePart: Bool = false
    ) -> [ReplayEquipmentNodeSpec] {
        var parts = ReplayAssetCatalog.requiredParts["equipment:ski:ski-assembly"]!
            .filter { $0 != dropPart }
            .sorted()
            .map { part in
                ReplayEquipmentPartSpec(
                    part: part,
                    sourceName: "equipment:ski:ski-assembly:\(part)",
                    exportedName: "equipment_ski_ski_assembly_\(part.replacingOccurrences(of: "-", with: "_"))",
                    materialRole: "equipment-dark"
                )
            }
        if duplicatePart, let first = parts.first {
            parts.append(first)
        }
        var nodes = [
            ReplayEquipmentNodeSpec(
                kind: "composite",
                sourceName: "equipment:ski:ski-assembly",
                exportedName: "equipment_ski_ski_assembly",
                parts: parts
            )
        ]
        for leaf in ReplayAssetCatalog.requiredLeafSourceNames(for: .skierg)
        where leaf != dropLeaf {
            nodes.append(
                ReplayEquipmentNodeSpec(
                    kind: "leaf",
                    sourceName: leaf,
                    exportedName: leaf.replacingOccurrences(of: ":", with: "_")
                        .replacingOccurrences(of: "-", with: "_"),
                    parts: []
                )
            )
        }
        return nodes
    }

    private func committedReferenceURL(_ relativePath: String) throws -> URL {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RowPlayStudio/Resources/ReplayReference/\(relativePath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing \(relativePath)")
        return path
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

    private func failure<Success>(
        from result: Result<Success, ReplayEquipmentContractFailure>
    ) -> ReplayEquipmentContractFailure? {
        guard case .failure(let failure) = result else { return nil }
        return failure
    }
}
