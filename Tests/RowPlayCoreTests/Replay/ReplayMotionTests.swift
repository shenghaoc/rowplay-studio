import XCTest
@testable import RowPlayCore

final class ReplayMotionTests: XCTestCase {
    private let tau = Double.pi * 2

    // MARK: - metersPerCycle

    func testMetersPerCycleCoversAllSports() {
        for sport in Sport.allCases {
            XCTAssertTrue(ReplayMotion.metersPerCycle(for: sport) > 0, "\(sport) must have positive cycle length")
        }
    }

    // MARK: - clampDt

    func testClampDtConvertsMsToSeconds() {
        XCTAssertEqual(ReplayMotion.clampDt(ms: 16.7), 0.0167, accuracy: 0.0001)
    }

    func testClampDtClampsLongDeltas() {
        XCTAssertEqual(ReplayMotion.clampDt(ms: 5000), 0.1)
    }

    func testClampDtReturnsZeroForInvalidInput() {
        XCTAssertEqual(ReplayMotion.clampDt(ms: 0), 0)
        XCTAssertEqual(ReplayMotion.clampDt(ms: -5), 0)
        XCTAssertEqual(ReplayMotion.clampDt(ms: .nan), 0)
        XCTAssertEqual(ReplayMotion.clampDt(ms: .infinity), 0)
    }

    // MARK: - dampFactor

    func testDampFactorIsZeroAtDtZero() {
        XCTAssertEqual(ReplayMotion.dampFactor(rate: 8, dt: 0), 0)
    }

    func testDampFactorApproachesOneForLargeDt() {
        XCTAssertEqual(ReplayMotion.dampFactor(rate: 8, dt: 10), 1, accuracy: 0.000001)
    }

    func testDampFactorIsFrameRateIndependent() {
        let rate: Double = 6
        let full = ReplayMotion.dampFactor(rate: rate, dt: 1.0 / 30.0)
        let half = ReplayMotion.dampFactor(rate: rate, dt: 1.0 / 60.0)
        // Applying the half factor twice: 1 - (1-half)^2 must equal the full factor.
        XCTAssertEqual(1 - (1 - half) * (1 - half), full, accuracy: 0.00000000001)
    }

    func testDampFactorNeverGoesNegativeForNegativeDt() {
        XCTAssertEqual(ReplayMotion.dampFactor(rate: 8, dt: -1), 0)
    }

    // MARK: - warpStrokePhase

    func testWarpStrokePhaseMapsCycleBoundariesToThemselves() {
        XCTAssertEqual(ReplayMotion.warpStrokePhase(0), 0, accuracy: 0.00000000001)
        XCTAssertEqual(ReplayMotion.warpStrokePhase(tau), tau, accuracy: 0.00000000001)
        XCTAssertEqual(ReplayMotion.warpStrokePhase(3 * tau), 3 * tau, accuracy: 0.00000000001)
    }

    func testWarpStrokePhaseMapsDriveEndToHalfCycle() {
        XCTAssertEqual(ReplayMotion.warpStrokePhase(0.4 * tau, driveFrac: 0.4), Double.pi, accuracy: 0.00000000001)
        XCTAssertEqual(ReplayMotion.warpStrokePhase(0.3 * tau, driveFrac: 0.3), Double.pi, accuracy: 0.00000000001)
    }

    func testWarpStrokePhaseIsMonotonicWithinCycle() {
        var prev = -1.0
        for u in stride(from: 0.0, through: 1.0, by: 0.01) {
            let w = ReplayMotion.warpStrokePhase(u * tau)
            XCTAssertTrue(w >= prev, "warpStrokePhase not monotonic at u=\(u)")
            prev = w
        }
    }

    func testWarpStrokePhaseDriveIsFasterThanRecovery() {
        let driveRate = ReplayMotion.warpStrokePhase(0.4 * tau) / (0.4 * tau)
        let recoveryRate = (ReplayMotion.warpStrokePhase(tau) - ReplayMotion.warpStrokePhase(0.4 * tau)) / (0.6 * tau)
        XCTAssertTrue(driveRate > recoveryRate)
    }

    func testWarpStrokePhaseHandlesInvalidDriveFractions() {
        XCTAssertTrue(ReplayMotion.warpStrokePhase(0.5 * tau, driveFrac: 0).isFinite)
        XCTAssertTrue(ReplayMotion.warpStrokePhase(0.5 * tau, driveFrac: 1).isFinite)
        XCTAssertEqual(
            ReplayMotion.warpStrokePhase(0.4 * tau, driveFrac: .nan),
            Double.pi,
            accuracy: 0.00000000001
        )
    }

    // MARK: - strokeSurge

    func testStrokeSurgeChecksAtCatchPeaksAtFinish() {
        XCTAssertEqual(ReplayMotion.strokeSurge(0), -1, accuracy: 0.00000000001)
        XCTAssertEqual(ReplayMotion.strokeSurge(Double.pi), 1, accuracy: 0.00000000001)
    }

    func testStrokeSurgeStaysWithinBounds() {
        for p in stride(from: 0.0, to: tau, by: 0.1) {
            let s = ReplayMotion.strokeSurge(p)
            XCTAssertTrue(s >= -1 && s <= 1, "strokeSurge out of bounds at phase \(p)")
        }
    }

    // MARK: - catchEvents

    func testCatchEventsReportsOneCatchAtCycleBoundary() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 0.9 * tau, next: 1.1 * tau), 1)
    }

    func testCatchEventsReportsNoneWithinCycle() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 0.2 * tau, next: 0.8 * tau), 0)
    }

    func testCatchEventsSuppressesSeekJumps() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 0, next: 50 * tau), 0)
    }

    func testCatchEventsIgnoresBackwardsMovement() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 2 * tau, next: tau), 0)
    }

    func testCatchEventsRejectsNonFiniteAndOutOfRangePhasesWithoutTrapping() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 0, next: .infinity), 0)
        XCTAssertEqual(ReplayMotion.catchEvents(prev: -.infinity, next: 0), 0)
        XCTAssertEqual(ReplayMotion.catchEvents(prev: .nan, next: tau), 0)
        XCTAssertEqual(
            ReplayMotion.catchEvents(
                prev: -Double.greatestFiniteMagnitude,
                next: Double.greatestFiniteMagnitude
            ),
            0
        )
    }

    func testCatchEventsValidatesCycleLimitBeforeIntegerConversion() {
        XCTAssertEqual(ReplayMotion.catchEvents(prev: 0.9 * tau, next: 1.1 * tau, maxCycles: 0), 0)
        XCTAssertEqual(
            ReplayMotion.catchEvents(prev: 0.9 * tau, next: 1.1 * tau, maxCycles: .max),
            1
        )
    }
}
