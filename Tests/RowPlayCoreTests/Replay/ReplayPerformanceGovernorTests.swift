import XCTest
@testable import RowPlayCore

final class ReplayPerformanceGovernorTests: XCTestCase {
    func testDefaultsMatchRequiredPolicy() {
        let governor = ReplayPerformanceGovernor(maximumLevel: 3)

        XCTAssertEqual(governor.floorBudgetMilliseconds, 22)
        XCTAssertEqual(governor.calibrationFrameCount, 30)
        XCTAssertEqual(governor.sustainedOverBudgetFrameCount, 60)
        XCTAssertEqual(governor.graceFrameCount, 90)
        XCTAssertEqual(governor.activeBudgetMilliseconds, 22)
        XCTAssertFalse(governor.isCalibrated)
        XCTAssertEqual(governor.level, 0)
    }

    func testHealthySixtyHertzFramesRemainAtLevelZero() {
        var governor = ReplayPerformanceGovernor(maximumLevel: 3)

        for _ in 0..<600 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 16.7))
        }

        XCTAssertTrue(governor.isCalibrated)
        XCTAssertEqual(governor.level, 0)
    }

    func testHealthySteadyThirtyHertzFramesRemainAtLevelZero() {
        var governor = ReplayPerformanceGovernor(maximumLevel: 3)

        for _ in 0..<600 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 33.4))
        }

        XCTAssertEqual(governor.activeBudgetMilliseconds, 44, accuracy: 1e-12)
        XCTAssertEqual(governor.level, 0)
    }

    func testSustainedSlowFramesDegradeByOneLevel() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 3,
            sustainedOverBudgetFrameCount: 10,
            graceFrameCount: 5
        )
        calibrate(&governor)

        let level = firstDegradation(in: &governor, interval: 40, limit: 100)

        XCTAssertEqual(level, 1)
        XCTAssertEqual(governor.level, 1)
    }

    func testOneSlowFrameDoesNotDegrade() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 3,
            sustainedOverBudgetFrameCount: 10
        )
        calibrate(&governor)

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 200))
        for _ in 0..<100 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 10))
        }

        XCTAssertEqual(governor.level, 0)
    }

    func testGracePeriodBlocksImmediateRepeatedDegradation() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 3,
            sustainedOverBudgetFrameCount: 1,
            graceFrameCount: 50
        )
        calibrate(&governor)
        XCTAssertEqual(firstDegradation(in: &governor, interval: 100, limit: 20), 1)

        for _ in 0..<50 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        }

        XCTAssertEqual(governor.level, 1)
    }

    func testMaximumLevelIsRespected() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 2,
            sustainedOverBudgetFrameCount: 2,
            graceFrameCount: 0
        )
        calibrate(&governor)

        for _ in 0..<500 {
            _ = governor.sample(frameIntervalMilliseconds: 100)
        }

        XCTAssertEqual(governor.level, 2)
    }

    func testLowCeilingCannotDegrade() {
        var governor = ReplayPerformanceGovernor(maximumLevel: 0)
        calibrate(&governor)

        for _ in 0..<500 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        }

        XCTAssertEqual(governor.level, 0)
    }

    func testInvalidAndAppBackgroundIntervalsMutateNothing() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 3,
            calibrationFrameCount: 3,
            sustainedOverBudgetFrameCount: 2
        )
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 16))
        let before = governor

        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, 250.01, 1_000] {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: invalid))
            XCTAssertEqual(governor, before)
        }

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 16))
        XCTAssertFalse(governor.isCalibrated)
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 16))
        XCTAssertTrue(governor.isCalibrated)
    }

    func testAlreadyOverloadedCalibrationStillDegrades() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 3,
            sustainedOverBudgetFrameCount: 5,
            graceFrameCount: 5
        )
        for _ in 0..<30 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        }

        XCTAssertEqual(governor.activeBudgetMilliseconds, 44, accuracy: 1e-12)
        for _ in 0..<4 {
            XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        }
        XCTAssertEqual(governor.sample(frameIntervalMilliseconds: 100), 1)
    }

    func testCalibrationUsesUpperMedianAndWorkingBudgetFormula() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 1,
            calibrationFrameCount: 4
        )

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 20))
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 25))
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 10))
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 15))

        // Sorting [20, 25, 10, 15] gives [10, 15, 20, 25]. The web
        // algorithm uses the upper median, 20, so the budget is 32.
        XCTAssertEqual(governor.activeBudgetMilliseconds, 32, accuracy: 1e-12)
    }

    func testExponentialMovingAverageUsesNinetyTenWeighting() {
        var governor = ReplayPerformanceGovernor(maximumLevel: 1)
        calibrate(&governor, interval: 16)

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 40))
        XCTAssertEqual(
            governor.smoothedFrameIntervalMilliseconds,
            18.4,
            accuracy: 1e-12
        )
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 40))
        XCTAssertEqual(
            governor.smoothedFrameIntervalMilliseconds,
            20.56,
            accuracy: 1e-12
        )
    }

    func testHealthyFrameResetsConsecutiveOverBudgetCounter() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 1,
            sustainedOverBudgetFrameCount: 4
        )
        calibrate(&governor, interval: 16)

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 120))
        XCTAssertEqual(governor.consecutiveOverBudgetFrames, 1)
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 1))
        XCTAssertEqual(governor.consecutiveOverBudgetFrames, 0)
        XCTAssertEqual(governor.level, 0)
    }

    func testDegradationCanResumeAfterGraceExpires() {
        var governor = ReplayPerformanceGovernor(
            maximumLevel: 2,
            floorBudgetMilliseconds: 1,
            calibrationFrameCount: 1,
            sustainedOverBudgetFrameCount: 1,
            graceFrameCount: 2
        )
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 1))
        XCTAssertEqual(governor.sample(frameIntervalMilliseconds: 100), 1)
        XCTAssertEqual(governor.remainingGraceFrames, 2)

        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        XCTAssertNil(governor.sample(frameIntervalMilliseconds: 100))
        XCTAssertEqual(governor.remainingGraceFrames, 0)
        XCTAssertEqual(governor.sample(frameIntervalMilliseconds: 100), 2)
    }

    func testResetClearsCalibrationAndDegradation() {
        let policy = ReplayPerformanceGovernor(
            maximumLevel: 3,
            calibrationFrameCount: 3,
            sustainedOverBudgetFrameCount: 1,
            graceFrameCount: 2
        )
        var governor = policy
        calibrate(&governor, frames: 3)
        XCTAssertEqual(firstDegradation(in: &governor, interval: 100, limit: 20), 1)

        governor.reset()

        XCTAssertEqual(governor, policy)
        XCTAssertEqual(governor.level, 0)
        XCTAssertFalse(governor.isCalibrated)
        XCTAssertEqual(governor.activeBudgetMilliseconds, 22)
    }

    private func calibrate(
        _ governor: inout ReplayPerformanceGovernor,
        frames: Int = 30,
        interval: Double = 16
    ) {
        for _ in 0..<frames {
            _ = governor.sample(frameIntervalMilliseconds: interval)
        }
    }

    private func firstDegradation(
        in governor: inout ReplayPerformanceGovernor,
        interval: Double,
        limit: Int
    ) -> Int? {
        for _ in 0..<limit {
            if let level = governor.sample(frameIntervalMilliseconds: interval) {
                return level
            }
        }
        XCTFail("Expected a degradation within \(limit) valid samples")
        return nil
    }
}
