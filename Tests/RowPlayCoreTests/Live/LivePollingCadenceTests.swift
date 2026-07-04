import XCTest
@testable import RowPlayCore

final class LivePollingCadenceTests: XCTestCase {

    // MARK: - Effective Interval

    func testVisibleUsesBaseInterval() {
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 30, isVisible: true), 30)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 60, isVisible: true), 60)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 120, isVisible: true), 120)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 300, isVisible: true), 300)
    }

    func testHiddenSlowsToMinimum300() {
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 30, isVisible: false), 300)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 60, isVisible: false), 300)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 120, isVisible: false), 300)
    }

    func testHiddenKeepsLargerIntervals() {
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 300, isVisible: false), 300)
        XCTAssertEqual(LivePollingCadence.effectiveInterval(baseInterval: 600, isVisible: false), 600)
    }

    // MARK: - Backoff

    func testZeroFailuresNoBackoff() {
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 0), 0)
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: -1), 0)
    }

    func testBackoffSteps() {
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 1), 30_000)
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 2), 60_000)
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 3), 120_000)
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 4), 300_000)
    }

    func testBackoffCapsAt300s() {
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 5), 300_000)
        XCTAssertEqual(LivePollingCadence.nextBackoffMs(consecutiveFailures: 100), 300_000)
    }

    // MARK: - Staleness Threshold

    func testStalenessThresholdIs2x() {
        XCTAssertEqual(LivePollingCadence.stalenessThreshold(intervalSec: 30), 60)
        XCTAssertEqual(LivePollingCadence.stalenessThreshold(intervalSec: 60), 120)
        XCTAssertEqual(LivePollingCadence.stalenessThreshold(intervalSec: 120), 240)
        XCTAssertEqual(LivePollingCadence.stalenessThreshold(intervalSec: 300), 600)
    }

    // MARK: - Interval Presets

    func testLiveIntervalsMatchWeb() {
        XCTAssertEqual(liveIntervals, [30, 60, 120, 300])
    }

    // MARK: - Random Mock Delay

    func testRandomMockDelayInRange() {
        for _ in 0 ..< 50 {
            let delay = LivePollingCadence.randomMockDelayMs()
            XCTAssertGreaterThanOrEqual(delay, 30_000)
            XCTAssertLessThan(delay, 180_000)
        }
    }
}
