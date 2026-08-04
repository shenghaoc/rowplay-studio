import XCTest
@testable import RowPlayCore

final class ReplayAthletePhaseMapTests: XCTestCase {
    func testClipFractionMapsDriveAndRecoveryMonotonically() {
        let driveEnd = 0.38
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(phase: 0, cycleFrac: 0, driveFrac: 0.4),
                authoredDriveEnd: driveEnd
            ),
            0,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(phase: 0, cycleFrac: 0.4, driveFrac: 0.4),
                authoredDriveEnd: driveEnd
            ),
            driveEnd,
            accuracy: 1e-12
        )
        var previous = -1.0
        for step in 0..<100 {
            let fraction = ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(
                    phase: 0,
                    cycleFrac: Double(step) / 100,
                    driveFrac: 0.4
                ),
                authoredDriveEnd: driveEnd
            )
            XCTAssertGreaterThanOrEqual(fraction, previous)
            previous = fraction
        }
    }

    func testClipFractionUsesPhaseAndFiniteFallbacks() {
        let sample = ReplayAthleteMotionSample(
            phase: .pi,
            cycleFrac: .nan,
            driveFrac: .infinity
        )
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(sample: sample, authoredDriveEnd: .nan),
            7.0 / 12.0,
            accuracy: 1e-12
        )
        XCTAssertTrue(ReplayAthletePhaseMap.isDrive(clipFraction: -0.9, authoredDriveEnd: 0.4))
        XCTAssertFalse(ReplayAthletePhaseMap.isDrive(clipFraction: 0.8, authoredDriveEnd: 0.4))
    }
}
