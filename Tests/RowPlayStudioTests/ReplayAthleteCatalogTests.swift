import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

final class ReplayAthleteCatalogTests: XCTestCase {
    func testSourceManifestPinsMergedUpstreamCommitAndHashes() throws {
        let data = try Data(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            ext: ReplayAthleteCatalog.sourceManifestExtension
        ))

        let parsed = ReplayAthleteCatalog.parseSourceManifest(data: data)
        guard case .success(let manifest) = parsed else {
            return XCTFail("Failed to parse source manifest")
        }
        XCTAssertEqual(manifest.pinnedCommit, Expected.commit)
        XCTAssertEqual(manifest.status, "merged")
        XCTAssertEqual(manifest.upstreamPR, 171)
        XCTAssertEqual(manifest.upstreamRepository, "https://github.com/shenghaoc/rowplay")
        XCTAssertEqual(manifest.glbSha256, Expected.glbSHA256)
        XCTAssertEqual(manifest.usdzSha256, Expected.usdzSHA256)
        XCTAssertEqual(manifest.contractSha256, Expected.contractSHA256)
        XCTAssertEqual(manifest.copiedUsdzSha256, Expected.usdzSHA256)
        XCTAssertTrue(ReplayAthleteCatalog.validateSourceManifest(manifest).isValid)
    }

    func testBundledContractAndUSDZHashesMatchThePin() throws {
        let contractURL = try resourceURL(
            name: ReplayAthleteCatalog.contractResourceName,
            ext: ReplayAthleteCatalog.contractExtension
        )
        let usdzURL = try resourceURL(
            name: ReplayAthleteCatalog.usdzResourceName,
            ext: ReplayAthleteCatalog.usdzExtension
        )
        let contractData = try Data(contentsOf: contractURL)
        let usdzData = try Data(contentsOf: usdzURL)
        let manifestData = try Data(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            ext: ReplayAthleteCatalog.sourceManifestExtension
        ))
        guard case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: manifestData) else {
            return XCTFail("Failed to parse source manifest")
        }
        XCTAssertEqual(
            ReplayAthleteCatalog.sha256Hex(of: contractData),
            manifest.contractSha256
        )
        XCTAssertEqual(
            ReplayAthleteCatalog.sha256Hex(of: usdzData),
            manifest.usdzSha256
        )

        let parsed = ReplayAthleteCatalog.parseContract(data: contractData)
        guard case .success(let contract) = parsed else {
            return XCTFail("Failed to parse athlete contract")
        }
        XCTAssertEqual(contract.orderedBoneNames, ReplayAthleteCatalog.orderedBoneNames)
        XCTAssertEqual(contract.schemaVersion, ReplayAthleteCatalog.contractSchemaVersion)
        XCTAssertEqual(contract.clips.count, 3)
        XCTAssertNotNil(contract.clip(for: .rower))
        XCTAssertNotNil(contract.clip(for: .skierg))
        XCTAssertNotNil(contract.clip(for: .bike))
        XCTAssertEqual(contract.clip(for: .rower)?.name, "rowplay-v4-row-cycle")
        XCTAssertEqual(contract.clip(for: .skierg)?.name, "rowplay-v4-ski-cycle")
        XCTAssertEqual(contract.clip(for: .bike)?.name, "rowplay-v4-bike-cycle")
        XCTAssertTrue(ReplayAthleteCatalog.validateContractHashes(contract, manifest: manifest).isValid)
    }

    func testClipFractionIsDeterministicAndBounded() {
        let sample = ReplayAthleteMotionSample(phase: 1.0, cycleFrac: 0.2, driveFrac: 0.4)
        let a = ReplayAthleteCatalog.clipFraction(sample: sample, authoredDriveEnd: 0.38)
        let b = ReplayAthleteCatalog.clipFraction(sample: sample, authoredDriveEnd: 0.38)
        XCTAssertEqual(a, b)
        XCTAssertGreaterThanOrEqual(a, 0)
        XCTAssertLessThan(a, 1)

        let catchSample = ReplayAthleteMotionSample(phase: 0, cycleFrac: 0, driveFrac: 0.4)
        XCTAssertEqual(
            ReplayAthleteCatalog.clipFraction(sample: catchSample, authoredDriveEnd: 0.38),
            0,
            accuracy: 1e-9
        )

        let finishSample = ReplayAthleteMotionSample(phase: 0, cycleFrac: 0.4, driveFrac: 0.4)
        XCTAssertEqual(
            ReplayAthleteCatalog.clipFraction(sample: finishSample, authoredDriveEnd: 0.38),
            0.38,
            accuracy: 1e-9
        )
    }

    func testDenseCycleSequencingRespectsDriveLandmarksForAllSports() throws {
        let contractURL = try resourceURL(
            name: ReplayAthleteCatalog.contractResourceName,
            ext: ReplayAthleteCatalog.contractExtension
        )
        let contractData = try Data(contentsOf: contractURL)
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

    private func resourceURL(name: String, ext: String) throws -> URL {
        // Production code loads via Bundle.module on RowPlayStudio. Tests also
        // resolve the committed resource path so pin checks do not depend on
        // test-bundle resource copying.
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RowPlayStudio/Resources/Replay3D/\(name).\(ext)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing \(name).\(ext)")
        return path
    }

    private enum Expected {
        static let commit = "da0dc73bf295871e9b362511cd5b2c9a9424b325"
        static let glbSHA256 = "73e0ece3e6c6de5a7a020a5097b172ca3e0ed8315c27ff604159b144fa90547b"
        static let usdzSHA256 = "934b0d3af0454f60a84dde76f95b77121919f5ad7cfc366684a670ae5d99658e"
        static let contractSHA256 = "e9fb56f372ac1ea44ee5ccaf1d00b5a975e1eb4a1a2ee7843ab9e53609fb189d"
    }
}
