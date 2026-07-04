import XCTest
@testable import RowPlayCore

final class LiveModeStateTests: XCTestCase {

    // MARK: - Initial State

    func testDefaultState() {
        let state = LiveModeState()
        XCTAssertEqual(state.status, .stopped)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.intervalSec, 60)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertNil(state.lastPollAt)
        XCTAssertNil(state.nextPollAt)
        XCTAssertFalse(state.hasWarning)
    }

    // MARK: - Start / Stop

    func testStartTransitionsToIdle() {
        var state = LiveModeState()
        state.start()
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.status, .idle)
    }

    func testStartResetsFailures() {
        var state = LiveModeState(consecutiveFailures: 5)
        state.start()
        XCTAssertEqual(state.consecutiveFailures, 0)
    }

    func testStopTransitionsToStopped() {
        var state = LiveModeState()
        state.start()
        state.stop()
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.status, .stopped)
        XCTAssertNil(state.nextPollAt)
    }

    // MARK: - Poll Lifecycle

    func testPollStartedFromIdle() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        XCTAssertEqual(state.status, .polling)
    }

    func testPollStartedIgnoredWhenPolling() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.pollStarted() // should be ignored
        XCTAssertEqual(state.status, .polling)
    }

    func testPollStartedIgnoredWhenStopped() {
        var state = LiveModeState()
        state.pollStarted()
        XCTAssertEqual(state.status, .stopped)
    }

    func testPollSucceededResetsState() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        let now = Date()
        state.pollSucceeded(at: now)
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertEqual(state.lastPollAt, now)
    }

    func testPollFailedIncrementsFailures() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.pollFailed()
        XCTAssertEqual(state.status, .error)
        XCTAssertEqual(state.consecutiveFailures, 1)

        state.pollStarted()
        state.pollFailed()
        XCTAssertEqual(state.consecutiveFailures, 2)
    }

    // MARK: - Warning

    func testHasWarningAtThreeFailures() {
        var state = LiveModeState()
        state.start()
        for _ in 0 ..< 3 {
            state.pollStarted()
            state.pollFailed()
        }
        XCTAssertTrue(state.hasWarning)
    }

    func testNoWarningBelowThreeFailures() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.pollFailed()
        state.pollStarted()
        state.pollFailed()
        XCTAssertFalse(state.hasWarning)
    }

    // MARK: - Interval Change

    func testIntervalChanged() {
        var state = LiveModeState()
        state.intervalChanged(120)
        XCTAssertEqual(state.intervalSec, 120)
    }

    func testIntervalChangedIgnoresInvalidIntervals() {
        var state = LiveModeState()
        state.intervalChanged(0)
        XCTAssertEqual(state.intervalSec, 60)
        state.intervalChanged(-30)
        XCTAssertEqual(state.intervalSec, 60)
        state.intervalChanged(45)
        XCTAssertEqual(state.intervalSec, 60)
    }

    func testInitialIntervalDefaultsWhenInvalid() {
        let zero = LiveModeState(intervalSec: 0)
        let negative = LiveModeState(intervalSec: -30)
        let unsupported = LiveModeState(intervalSec: 45)
        XCTAssertEqual(zero.intervalSec, 60)
        XCTAssertEqual(negative.intervalSec, 60)
        XCTAssertEqual(unsupported.intervalSec, 60)
    }

    // MARK: - Tick Scheduled

    func testTickScheduled() {
        var state = LiveModeState()
        let future = Date().addingTimeInterval(60)
        state.tickScheduled(at: future)
        XCTAssertEqual(state.nextPollAt, future)
    }

    // MARK: - Stale Detection

    func testIsStaleWhenExceedsThreshold() {
        let state = LiveModeState(intervalSec: 60)
        // Threshold is 2× interval = 120s
        XCTAssertTrue(state.isStale(lastSampleAge: 121))
        XCTAssertTrue(state.isStale(lastSampleAge: 300))
    }

    func testIsNotStaleWithinThreshold() {
        let state = LiveModeState(intervalSec: 60)
        XCTAssertFalse(state.isStale(lastSampleAge: 60))
        XCTAssertFalse(state.isStale(lastSampleAge: 119))
    }

    func testStaleThresholdUpdatesWithInterval() {
        var state = LiveModeState(intervalSec: 30)
        // Threshold = 60s
        XCTAssertTrue(state.isStale(lastSampleAge: 61))
        XCTAssertFalse(state.isStale(lastSampleAge: 59))

        state.intervalChanged(300)
        // Threshold = 600s
        XCTAssertTrue(state.isStale(lastSampleAge: 601))
        XCTAssertFalse(state.isStale(lastSampleAge: 599))
    }

    // MARK: - Error Recovery

    func testErrorCanRetry() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.pollFailed()
        XCTAssertEqual(state.status, .error)

        // Can retry from error
        state.pollStarted()
        XCTAssertEqual(state.status, .polling)
    }

    func testSuccessResetsFailuresFromError() {
        var state = LiveModeState()
        state.start()
        for _ in 0 ..< 5 {
            state.pollStarted()
            state.pollFailed()
        }
        XCTAssertEqual(state.consecutiveFailures, 5)

        state.pollStarted()
        state.pollSucceeded()
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertFalse(state.hasWarning)
    }

    func testPollSucceededIgnoredAfterStop() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.stop()
        state.pollSucceeded(at: Date())
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.status, .stopped)
        XCTAssertNil(state.lastPollAt)
    }

    func testPollFailedIgnoredAfterStop() {
        var state = LiveModeState()
        state.start()
        state.pollStarted()
        state.stop()
        state.pollFailed(at: Date())
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertNil(state.lastPollAt)
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = LiveModeState(enabled: true, status: .idle, intervalSec: 60)
        let b = LiveModeState(enabled: true, status: .idle, intervalSec: 60)
        let c = LiveModeState(enabled: true, status: .idle, intervalSec: 120)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
