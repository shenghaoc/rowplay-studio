import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

final class ReplayAthleteCatalogTests: XCTestCase {
    /// The exact RowPlay main commit the reference bundle is pinned to.
    /// Updated only by re-running `script/sync_rowplay_reference.py`.
    static let pinnedRowPlayMain = "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"

    func testSourceManifestPinsCurrentMainAndHashes() throws {
        let data = try Data(contentsOf: try referenceURL("athlete/rowplay-athlete-source.json"))

        let parsed = ReplayAthleteCatalog.parseSourceManifest(data: data)
        guard case .success(let manifest) = parsed else {
            return XCTFail("Failed to parse source manifest")
        }
        XCTAssertEqual(manifest.pinnedCommit, Self.pinnedRowPlayMain)
        XCTAssertEqual(manifest.contractSchema, "rowplay.replay.athlete.v4")
        XCTAssertEqual(manifest.semanticBoneCount, 19)
        XCTAssertEqual(manifest.helperCount, 32)
        XCTAssertEqual(manifest.totalBoneCount, 51)
        XCTAssertTrue(ReplayAthleteCatalog.validateSourceManifest(manifest).isValid)
    }

    func testBundledContractAndUSDZHashesMatchThePin() throws {
        let contractData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        let usdzData = try Data(contentsOf: try referenceURL("athlete/rowplay-athlete-v4.usdz"))
        let manifestData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-source.json")
        )
        guard case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: manifestData) else {
            return XCTFail("Failed to parse source manifest")
        }
        XCTAssertEqual(
            ReplayBundledResourceSupport.sha256Hex(of: contractData),
            manifest.contractSha256
        )
        XCTAssertEqual(
            ReplayBundledResourceSupport.sha256Hex(of: usdzData),
            manifest.usdzSha256
        )

        let parsed = ReplayAthleteCatalog.parseContract(data: contractData)
        guard case .success(let contract) = parsed else {
            return XCTFail("Failed to parse athlete contract")
        }
        XCTAssertEqual(contract.schemaVersion, ReplayAthleteCatalog.contractSchemaVersion)
        XCTAssertEqual(contract.semanticBones.count, 19)
        XCTAssertEqual(contract.helpers.count, 32)
        XCTAssertEqual(contract.totalBoneCount, 51)
        XCTAssertEqual(contract.clips.count, 3)
        XCTAssertEqual(contract.clip(for: .rower)?.name, "rowplay-v4-row-cycle")
        XCTAssertEqual(contract.clip(for: .skierg)?.name, "rowplay-v4-ski-cycle")
        XCTAssertEqual(contract.clip(for: .bike)?.name, "rowplay-v4-bike-cycle")
        XCTAssertEqual(contract.surfaces.count, 8)
        XCTAssertEqual(contract.meshName, ReplayAthleteCatalog.skinnedMeshName)
        for role in ReplayAthleteCatalog.requiredSurfaceRoles {
            XCTAssertTrue(
                contract.surfaces.contains { $0.role == role },
                "missing surface role \(role)"
            )
        }
        XCTAssertTrue(ReplayAthleteCatalog.validateContract(contract, manifest: manifest).isValid)
    }

    func testNativeDerivativeManifestSealsPinnedInputsEightRolesAndRuntimeBytes() throws {
        let sourceData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-source.json")
        )
        let contractData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        let nativeData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4-native.json")
        )
        let nativeUsdz = try referenceURL("athlete/rowplay-athlete-v4-native.usdz")
        guard case .success(let source) = ReplayAthleteCatalog.parseSourceManifest(data: sourceData),
              case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData),
              case .success(let native) = ReplayAthleteCatalog.parseNativeManifest(data: nativeData) else {
            return XCTFail("native athlete manifests must parse")
        }

        XCTAssertTrue(
            ReplayAthleteCatalog.validateNativeManifest(
                native,
                source: source,
                contract: contract
            ).isValid
        )
        XCTAssertEqual(native.sourceCommit, Self.pinnedRowPlayMain)
        XCTAssertEqual(native.sourceGlbSha256, source.glbSha256)
        XCTAssertEqual(native.sourceUsdzSha256, source.usdzSha256)
        XCTAssertEqual(native.sourceContractSha256, source.contractSha256)
        XCTAssertEqual(native.surfaceRoles, ReplayAthleteSurfaceRole.allCases)
        XCTAssertEqual(
            native.runtimeMaterialNames,
            ReplayAthleteSurfaceRole.allCases.map(\.runtimeMaterialName)
        )
        XCTAssertEqual(native.materialSlotCount, 8)
        XCTAssertEqual(native.skinnedMeshCount, 1)
        XCTAssertEqual(
            try ReplayBundledResourceSupport.sha256Hex(contentsOf: nativeUsdz),
            native.runtimeUsdzSha256
        )
        XCTAssertEqual(
            try XCTUnwrap(nativeUsdz.resourceValues(forKeys: [.fileSizeKey]).fileSize),
            native.runtimeUsdzByteCount
        )
    }

    func testContractRejectsUnexpectedRuntimeMeshName() throws {
        let original = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var mesh = try XCTUnwrap(root["mesh"] as? [String: Any])
        mesh["meshName"] = "unexpected-athlete"
        root["mesh"] = mesh
        let mutated = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: mutated) else {
            return XCTFail("The mutation should remain structurally parseable")
        }
        let sourceData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-source.json")
        )
        guard case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: sourceData) else {
            return XCTFail("source manifest parse failed")
        }

        XCTAssertEqual(
            ReplayAthleteCatalog.validateContract(contract, manifest: manifest).failures,
            [.invalidContract("mesh.meshName")]
        )
    }

    func testContractRequiresUniqueContactRolesAndResolvableBones() throws {
        let original = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var contacts = try XCTUnwrap(root["contacts"] as? [[String: Any]])
        contacts.append(contacts[0])
        root["contacts"] = contacts
        let duplicate = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        XCTAssertEqual(
            failure(ReplayAthleteCatalog.parseContract(data: duplicate)),
            .duplicateContact("left-hand")
        )

        contacts.removeLast()
        contacts[0]["bone"] = "v4MissingHand"
        root["contacts"] = contacts
        let missingBone = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        XCTAssertEqual(
            failure(ReplayAthleteCatalog.parseContract(data: missingBone)),
            .missingBone("v4MissingHand")
        )
    }

    func testMotionManifestParserPreservesTypedCoreLoadErrors() throws {
        let original = try Data(
            contentsOf: try referenceURL("motion/rowplay-motion-manifest.json")
        )
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        root["formatVersion"] = 999
        let changed = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        XCTAssertEqual(
            failure(ReplayAthleteCatalog.parseMotionManifest(data: changed)),
            .motionTableLoad(.unsupportedFormatVersion(999))
        )
    }

    func testHelperHierarchyDescribesTenDigitChains() throws {
        let contractData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData) else {
            return XCTFail("contract parse failed")
        }
        for side in ["Left", "Right"] {
            XCTAssertEqual(contract.parentName(of: "v4\(side)Fingers"), "v4\(side)Hand")
            XCTAssertEqual(contract.parentName(of: "v4\(side)Thumb"), "v4\(side)Hand")
            for digit in ["Index", "Middle", "Ring", "Pinky"] {
                XCTAssertEqual(
                    contract.parentName(of: "v4\(side)\(digit)Proximal"),
                    "v4\(side)Fingers"
                )
                XCTAssertEqual(
                    contract.parentName(of: "v4\(side)\(digit)Intermediate"),
                    "v4\(side)\(digit)Proximal"
                )
                XCTAssertEqual(
                    contract.parentName(of: "v4\(side)\(digit)Distal"),
                    "v4\(side)\(digit)Intermediate"
                )
            }
            XCTAssertEqual(
                contract.parentName(of: "v4\(side)ThumbIntermediate"),
                "v4\(side)Thumb"
            )
            XCTAssertEqual(
                contract.parentName(of: "v4\(side)ThumbDistal"),
                "v4\(side)ThumbIntermediate"
            )
        }
    }

    func testBundledMotionTableMatchesContract() throws {
        let contractData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData) else {
            return XCTFail("contract parse failed")
        }
        let manifestData = try Data(
            contentsOf: try referenceURL("motion/rowplay-motion-manifest.json")
        )
        let binData = try Data(contentsOf: try referenceURL("motion/rowplay-motion.bin"))
        let sourceData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-source.json")
        )
        guard case .success(let source) = ReplayAthleteCatalog.parseSourceManifest(data: sourceData),
              case .success(let motion) = ReplayAthleteCatalog.parseMotionManifest(data: manifestData) else {
            return XCTFail("reference manifests must parse")
        }
        XCTAssertTrue(
            ReplayAthleteCatalog.validateMotionManifest(
                motion,
                source: source,
                binData: binData
            ).isValid
        )
        XCTAssertEqual(motion.sourceCommit, source.pinnedCommit)
        XCTAssertEqual(motion.sourceGlbSha256, source.glbSha256)
        XCTAssertEqual(motion.motionBinByteCount, binData.count)
        let table = try ReplayAthleteMotionTable(manifest: motion, binData: binData)
        XCTAssertEqual(table.boneNames, contract.semanticBoneNames)
        XCTAssertEqual(table.sourceCommit, Self.pinnedRowPlayMain)
        XCTAssertGreaterThanOrEqual(table.samplesPerSport, 257)
        for sport in [Sport.rower, .skierg, .bike] {
            let tableClip = try XCTUnwrap(table.clips[sport])
            let contractClip = try XCTUnwrap(contract.clip(for: sport))
            XCTAssertEqual(tableClip.clipName, contractClip.name)
            XCTAssertEqual(tableClip.driveEnd, contractClip.driveEnd, accuracy: 1e-12)
        }
    }

    func testClipFractionIsDeterministicAndBounded() {
        let sample = ReplayAthleteMotionSample(phase: 1.0, cycleFrac: 0.2, driveFrac: 0.4)
        let a = ReplayAthletePhaseMap.clipFraction(sample: sample, authoredDriveEnd: 0.38)
        let b = ReplayAthletePhaseMap.clipFraction(sample: sample, authoredDriveEnd: 0.38)
        XCTAssertEqual(a, b)
        XCTAssertGreaterThanOrEqual(a, 0)
        XCTAssertLessThan(a, 1)

        let catchSample = ReplayAthleteMotionSample(phase: 0, cycleFrac: 0, driveFrac: 0.4)
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(sample: catchSample, authoredDriveEnd: 0.38),
            0,
            accuracy: 1e-9
        )

        let finishSample = ReplayAthleteMotionSample(phase: 0, cycleFrac: 0.4, driveFrac: 0.4)
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(sample: finishSample, authoredDriveEnd: 0.38),
            0.38,
            accuracy: 1e-9
        )
    }

    func testDenseCycleSequencingRespectsDriveLandmarksForAllSports() throws {
        let contractData = try Data(
            contentsOf: try referenceURL("athlete/rowplay-athlete-v4.contract.json")
        )
        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData) else {
            return XCTFail("contract parse failed")
        }
        let adapter = ReplayAthletePoseAdapter(contract: contract)

        for sport in [Sport.rower, .skierg, .bike] {
            let clip = try XCTUnwrap(contract.clip(for: sport))
            var previous = -1.0
            // Stay inside one open cycle [0, 1) so the loop wrap is not treated
            // as a discontinuity failure.
            for step in 0..<20 {
                let cycle = Double(step) / 20.0
                let sample = ReplayAthleteMotionSample(
                    phase: cycle * 2 * .pi,
                    cycleFrac: cycle,
                    driveFrac: clip.driveEnd
                )
                let fraction = adapter.clipFraction(sport: sport, sample: sample)
                XCTAssertGreaterThanOrEqual(fraction, previous - 1e-9, "\(sport) non-monotonic")
                previous = fraction
                XCTAssertGreaterThanOrEqual(fraction, 0)
                XCTAssertLessThan(fraction, 1.0 + 1e-9)
            }
            // Mid-drive is before driveEnd; late recovery is after.
            let midDrive = adapter.clipFraction(
                sport: sport,
                sample: ReplayAthleteMotionSample(
                    phase: 0,
                    cycleFrac: clip.driveEnd * 0.5,
                    driveFrac: clip.driveEnd
                )
            )
            let lateRecovery = adapter.clipFraction(
                sport: sport,
                sample: ReplayAthleteMotionSample(
                    phase: 0,
                    cycleFrac: clip.driveEnd + (1 - clip.driveEnd) * 0.75,
                    driveFrac: clip.driveEnd
                )
            )
            XCTAssertTrue(adapter.isDrive(sport: sport, clipFraction: midDrive))
            XCTAssertFalse(adapter.isDrive(sport: sport, clipFraction: lateRecovery))
        }
    }

    private func referenceURL(_ relativePath: String) throws -> URL {
        // Production code loads via Bundle.module on RowPlayStudio.  Tests
        // also resolve the committed resource path so pin checks do not
        // depend on test-bundle resource copying.
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RowPlayStudio/Resources/ReplayReference/\(relativePath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing \(relativePath)")
        return path
    }

    private func failure<Success>(
        _ result: Result<Success, ReplayAthleteValidationFailure>
    ) -> ReplayAthleteValidationFailure? {
        guard case .failure(let failure) = result else { return nil }
        return failure
    }
}
