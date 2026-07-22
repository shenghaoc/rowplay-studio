import Foundation
import RowPlayCore
import XCTest
@testable import RowPlayStudio

final class ReplayAthleteCatalogTests: XCTestCase {
    func testSourceManifestPinsProvisionalUpstreamCommitAndHashes() throws {
        let data = try Data(contentsOf: try resourceURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            ext: ReplayAthleteCatalog.sourceManifestExtension
        ))

        let parsed = ReplayAthleteCatalog.parseSourceManifest(data: data)
        guard case .success(let manifest) = parsed else {
            return XCTFail("Failed to parse source manifest")
        }
        XCTAssertEqual(manifest.pinnedCommit, ReplayAthleteCatalog.pinnedCommit)
        XCTAssertEqual(manifest.status, "provisional")
        XCTAssertEqual(manifest.upstreamPR, 171)
        XCTAssertEqual(manifest.glbSha256, ReplayAthleteCatalog.expectedGLBSHA256)
        XCTAssertEqual(manifest.usdzSha256, ReplayAthleteCatalog.expectedUSDZSHA256)
        XCTAssertEqual(manifest.contractSha256, ReplayAthleteCatalog.expectedContractSHA256)
        XCTAssertEqual(manifest.copiedUsdzSha256, ReplayAthleteCatalog.expectedUSDZSHA256)
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
        XCTAssertEqual(
            ReplayAthleteCatalog.sha256Hex(of: contractData),
            ReplayAthleteCatalog.expectedContractSHA256
        )
        XCTAssertEqual(
            ReplayAthleteCatalog.sha256Hex(of: usdzData),
            ReplayAthleteCatalog.expectedUSDZSHA256
        )

        let parsed = ReplayAthleteCatalog.parseContract(data: contractData)
        guard case .success(let contract) = parsed else {
            return XCTFail("Failed to parse athlete contract")
        }
        XCTAssertEqual(contract.orderedBoneNames, ReplayAthleteCatalog.orderedBoneNames)
        XCTAssertEqual(contract.clips.count, 3)
        XCTAssertNotNil(contract.clip(for: .rower))
        XCTAssertNotNil(contract.clip(for: .skierg))
        XCTAssertNotNil(contract.clip(for: .bike))
        XCTAssertTrue(ReplayAthleteCatalog.validateContractHashes(contract).isValid)
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
}
