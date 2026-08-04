import AppKit
import RealityKit
import RowPlayCore
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayBundledRigVisualProviderTests: XCTestCase {
    func testProviderPrevalidatesAndClonesEveryRequiredVisual() throws {
        let contract = skiContract()
        let required = try requiredVisuals(in: contract)
        let provider = try ReplayBundledRigVisualProvider(
            root: root(for: required),
            contract: contract
        )

        XCTAssertEqual(provider.validatedSourceNames, Set(required.map(\.sourceName)))
        for visual in required {
            let first = try XCTUnwrap(provider.cloneVisual(named: visual.sourceName))
            let second = try XCTUnwrap(provider.cloneVisual(named: visual.sourceName))
            XCTAssertFalse(first === second, visual.sourceName)
            XCTAssertTrue(ReplayAssetGeometry.hasModel(in: first), visual.sourceName)
        }
    }

    func testProviderRejectsMissingRequiredPartEntityWithTypedFailure() throws {
        let contract = skiContract()
        let required = try requiredVisuals(in: contract)
        let missing = try XCTUnwrap(required.first {
            $0.sourceName == "equipment:ski:ski-assembly:binding-toe"
        })

        XCTAssertThrowsError(try ReplayBundledRigVisualProvider(
            root: root(for: required, omitting: missing.sourceName),
            contract: contract
        )) { error in
            XCTAssertEqual(
                error as? ReplayBundledRigVisualProviderFailure,
                .missingEntity(
                    sourceName: missing.sourceName,
                    exportedName: missing.exportedName
                )
            )
        }
    }

    func testProviderRejectsRequiredPartWithoutModelWithTypedFailure() throws {
        let contract = skiContract()
        let required = try requiredVisuals(in: contract)
        let modelLess = try XCTUnwrap(required.first {
            $0.sourceName == "equipment:ski:ski-assembly:binding-heel"
        })

        XCTAssertThrowsError(try ReplayBundledRigVisualProvider(
            root: root(for: required, withoutModel: modelLess.sourceName),
            contract: contract
        )) { error in
            XCTAssertEqual(
                error as? ReplayBundledRigVisualProviderFailure,
                .missingModel(
                    sourceName: modelLess.sourceName,
                    exportedName: modelLess.exportedName
                )
            )
        }
    }

    func testAccentRecursesThroughBundledVisualHierarchy() throws {
        let root = Entity()
        let parent = ModelEntity(
            mesh: .generateBox(size: 0.02),
            materials: [PhysicallyBasedMaterial()]
        )
        let child = ModelEntity(
            mesh: .generateBox(size: 0.01),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        parent.addChild(child)
        root.addChild(parent)

        let accent = NSColor(
            calibratedRed: 0.2,
            green: 0.6,
            blue: 0.9,
            alpha: 1
        )
        ReplayBundledRigVisualProvider.applyAccent(accent, to: root)

        let parentModel = try XCTUnwrap(parent.components[ModelComponent.self])
        let parentMaterial = try XCTUnwrap(
            parentModel.materials.first as? PhysicallyBasedMaterial
        )
        assertColor(parentMaterial.baseColor.tint, equals: accent)

        let childModel = try XCTUnwrap(child.components[ModelComponent.self])
        let childMaterial = try XCTUnwrap(childModel.materials.first as? SimpleMaterial)
        assertColor(childMaterial.color.tint, equals: accent)
    }

    private func skiContract() -> ReplayEquipmentPackageContract {
        let composite = "equipment:ski:ski-assembly"
        let parts = ReplayAssetCatalog.requiredParts[composite]!.sorted().map { part in
            ReplayEquipmentPartSpec(
                part: part,
                sourceName: "\(composite):\(part)",
                exportedName: "ski_\(part.replacingOccurrences(of: "-", with: "_"))",
                materialRole: "equipment-dark"
            )
        }
        var nodes = [ReplayEquipmentNodeSpec(
            kind: "composite",
            sourceName: composite,
            exportedName: "ski_assembly",
            parts: parts
        )]
        nodes.append(contentsOf: ReplayAssetCatalog.requiredLeafSourceNames(for: .skierg).map {
            ReplayEquipmentNodeSpec(
                kind: "leaf",
                sourceName: $0,
                exportedName: $0.replacingOccurrences(of: ":", with: "_"),
                parts: []
            )
        })
        return ReplayEquipmentPackageContract(
            sport: .skierg,
            sourceCommit: String(repeating: "a", count: 40),
            sourceGlbSha256: String(repeating: "b", count: 64),
            nodes: nodes
        )
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

    private func root(
        for visuals: [ReplayEquipmentRequiredVisualSpec],
        omitting omittedSourceName: String? = nil,
        withoutModel modelLessSourceName: String? = nil
    ) -> Entity {
        let root = Entity()
        for visual in visuals where visual.sourceName != omittedSourceName {
            let entity: Entity
            if visual.sourceName == modelLessSourceName {
                entity = Entity()
            } else {
                entity = ModelEntity(
                    mesh: .generateBox(size: 0.01),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
            }
            entity.name = visual.exportedName
            root.addChild(entity)
        }
        return root
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actualRGB = actual.usingColorSpace(.deviceRGB),
              let expectedRGB = expected.usingColorSpace(.deviceRGB) else {
            return XCTFail("Expected RGB colors", file: file, line: line)
        }
        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 1e-6, file: file, line: line)
    }
}
