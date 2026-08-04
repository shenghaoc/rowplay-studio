import Foundation
import XCTest
@testable import RowPlayCore

final class ReplayAthleteMotionTableTests: XCTestCase {
    func testLoadsAndInterpolatesWrappedMotionWithoutAllocatingOutput() throws {
        let manifest = """
        {
          "formatVersion": 2,
          "boneNames": ["hips"],
          "samplesPerSport": 2,
          "sports": ["rower"],
          "sourceCommit": "fixture",
          "clips": [{
            "sport": "rower",
            "clipName": "row-cycle",
            "durationSeconds": 2.0,
            "driveEnd": 0.4,
            "phaseLandmarks": {"catch": 0.0}
          }]
        }
        """
        let values: [Float] = [
            0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
            2, 4, 6, 0, 0, 1, 0, 3, 3, 3,
        ]
        let table = try ReplayAthleteMotionTable(
            manifestData: Data(manifest.utf8),
            binData: binaryData(values)
        )

        XCTAssertEqual(table.boneNames, ["hips"])
        XCTAssertEqual(table.boneIndex(named: "hips"), 0)
        XCTAssertEqual(table.clips[.rower]?.clipName, "row-cycle")

        var output = [ReplayAthleteBoneTransform()]
        XCTAssertTrue(table.sample(sport: .rower, fraction: 0.25, into: &output))
        XCTAssertEqual(output[0].translation, SIMD3(1, 2, 3))
        XCTAssertEqual(output[0].scale, SIMD3(2, 2, 2))
        let rotated = output[0].rotation.act(SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(rotated.x, 0, accuracy: 1e-12)
        XCTAssertEqual(rotated.y, 1, accuracy: 1e-12)

        XCTAssertTrue(table.sample(sport: .rower, fraction: -0.25, into: &output))
        XCTAssertEqual(output[0].translation, SIMD3(1, 2, 3))
        XCTAssertEqual(ReplayAthleteMotionTable.wrapUnit(.infinity), 0)
    }

    func testRejectsPayloadSizeAndNonFiniteValues() throws {
        let manifest = """
        {"formatVersion":2,"boneNames":["hips"],"samplesPerSport":2,"sourceCommit":"fixture",
        "sports":["rower"],"clips":[{"sport":"rower","clipName":"row-cycle",
        "durationSeconds":2,"driveEnd":0.4,"phaseLandmarks":{"catch":0}}]}
        """
        XCTAssertThrowsError(try ReplayAthleteMotionTable(
            manifestData: Data(manifest.utf8),
            binData: Data()
        )) { error in
            XCTAssertEqual(
                error as? ReplayAthleteMotionTable.LoadError,
                .payloadSizeMismatch(expected: 80, actual: 0)
            )
        }

        var values = [Float](repeating: 0, count: 20)
        values[0] = .nan
        XCTAssertThrowsError(try ReplayAthleteMotionTable(
            manifestData: Data(manifest.utf8),
            binData: binaryData(values)
        )) { error in
            XCTAssertEqual(error as? ReplayAthleteMotionTable.LoadError, .nonFinitePayload)
        }
    }

    func testRejectsIncompleteManifestAndReportsSampleBufferMismatch() throws {
        let missingMetadata = """
        {"formatVersion":2,"boneNames":["hips"],"samplesPerSport":2,
        "sports":["rower"],"clips":[{"sport":"rower","clipName":"row-cycle",
        "durationSeconds":2,"driveEnd":0.4}]}
        """
        XCTAssertThrowsError(try ReplayAthleteMotionTable(
            manifestData: Data(missingMetadata.utf8),
            binData: binaryData([Float](repeating: 0, count: 20))
        )) { error in
            XCTAssertEqual(
                error as? ReplayAthleteMotionTable.LoadError,
                .invalidManifest("sourceCommit")
            )
        }

        let missingLandmarks = """
        {"formatVersion":2,"boneNames":["hips"],"samplesPerSport":2,"sourceCommit":"fixture",
        "sports":["rower"],"clips":[{"sport":"rower","clipName":"row-cycle",
        "durationSeconds":2,"driveEnd":0.4}]}
        """
        XCTAssertThrowsError(try ReplayAthleteMotionTable(
            manifestData: Data(missingLandmarks.utf8),
            binData: binaryData([Float](repeating: 0, count: 20))
        )) { error in
            XCTAssertEqual(
                error as? ReplayAthleteMotionTable.LoadError,
                .invalidManifest("clip entry")
            )
        }

        let validManifest = """
        {"formatVersion":2,"boneNames":["hips"],"samplesPerSport":2,"sourceCommit":"fixture",
        "sports":["rower"],"clips":[{"sport":"rower","clipName":"row-cycle",
        "durationSeconds":2,"driveEnd":0.4,"phaseLandmarks":{"catch":0}}]}
        """
        let table = try ReplayAthleteMotionTable(
            manifestData: Data(validManifest.utf8),
            binData: binaryData([Float](repeating: 0, count: 20))
        )
        var wrongSize: [ReplayAthleteBoneTransform] = []
        XCTAssertFalse(table.sample(sport: .rower, fraction: 0, into: &wrongSize))
        let sentinel = ReplayAthleteBoneTransform(translation: SIMD3(4, 5, 6))
        var correctSize = [sentinel]
        XCTAssertFalse(table.sample(sport: .bike, fraction: 0, into: &correctSize))
        XCTAssertEqual(correctSize, [sentinel])
    }

    func testManifestRejectsClipForSportMissingFromSportsArray() throws {
        let manifest = """
        {"formatVersion":2,"boneNames":["hips"],"samplesPerSport":2,"sourceCommit":"fixture",
        "sports":["rower"],"clips":[
          {"sport":"rower","clipName":"row-cycle","durationSeconds":2,
           "driveEnd":0.4,"phaseLandmarks":{"catch":0}},
          {"sport":"bike","clipName":"bike-cycle","durationSeconds":2,
           "driveEnd":0.5,"phaseLandmarks":{"top":0}}
        ]}
        """

        XCTAssertThrowsError(
            try ReplayAthleteMotionTable.parseManifest(data: Data(manifest.utf8))
        ) { error in
            XCTAssertEqual(
                error as? ReplayAthleteMotionTable.LoadError,
                .invalidManifest("clip for undeclared sport bike")
            )
        }
    }

    private func binaryData(_ values: [Float]) -> Data {
        let littleEndian = values.map { $0.bitPattern.littleEndian }
        return littleEndian.withUnsafeBytes { Data($0) }
    }
}
