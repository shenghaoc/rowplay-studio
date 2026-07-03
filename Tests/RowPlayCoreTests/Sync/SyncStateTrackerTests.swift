import XCTest
@testable import RowPlayCore

@available(macOS 14.0, *)
final class SyncStateTrackerTests: XCTestCase {
    private var cache: InMemoryWorkoutCache!
    private var tracker: SyncStateTracker!

    override func setUp() {
        super.setUp()
        cache = InMemoryWorkoutCache()
        tracker = SyncStateTracker(cache: cache)
    }

    override func tearDown() {
        tracker = nil
        cache = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialState() {
        XCTAssertEqual(tracker.state, SyncState())
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNil(tracker.state.lastSyncDate)
        XCTAssertNil(tracker.state.lastError)
        XCTAssertEqual(tracker.state.totalWorkouts, 0)
    }

    func testInitialWorkoutCountFromCache() throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        let freshTracker = SyncStateTracker(cache: cache)
        XCTAssertEqual(freshTracker.state.totalWorkouts, workouts.count)
    }

    // MARK: - Sync lifecycle

    func testSyncStarted() {
        tracker.syncStarted()
        XCTAssertTrue(tracker.state.inProgress)
        XCTAssertNil(tracker.state.lastError)
        XCTAssertNil(tracker.state.lastErrorDate)
    }

    func testSyncCompleted() {
        tracker.syncStarted()
        tracker.syncCompleted()
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastSyncDate)
        XCTAssertNil(tracker.state.lastError)
    }

    func testSyncFailed() {
        tracker.syncStarted()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])
        tracker.syncFailed(error: error)
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastError)
        XCTAssertNotNil(tracker.state.lastErrorDate)
        XCTAssertNil(tracker.state.lastSyncDate)
    }

    func testSyncFailedRedactsError() {
        tracker.syncStarted()
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Authorization: Bearer abcdef1234567890abcdef1234567890"
        ])
        tracker.syncFailed(error: error)
        XCTAssertNotNil(tracker.state.lastError)
        // The error should be redacted — should not contain the token.
        XCTAssertFalse(tracker.state.lastError?.contains("abcdef1234567890abcdef1234567890") ?? false)
        XCTAssertTrue(tracker.state.lastError?.contains("[REDACTED]") ?? false)
    }

    // MARK: - State transitions

    func testRetryAfterError() {
        tracker.syncStarted()
        tracker.syncFailed(error: NSError(domain: "test", code: 1))
        // Retry
        tracker.syncStarted()
        XCTAssertNil(tracker.state.lastError)
        XCTAssertTrue(tracker.state.inProgress)

        tracker.syncCompleted()
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastSyncDate)
        XCTAssertNil(tracker.state.lastError)
    }

    func testRefreshWorkoutCount() throws {
        XCTAssertEqual(tracker.state.totalWorkouts, 0)
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        tracker.refreshWorkoutCount()
        XCTAssertEqual(tracker.state.totalWorkouts, workouts.count)
    }

    func testSyncCompletedRefreshesWorkoutCount() throws {
        try cache.saveWorkouts([DemoWorkoutLibrary.details[0].workout])
        tracker.syncStarted()
        try cache.saveWorkouts(DemoWorkoutLibrary.details.map(\.workout))
        tracker.syncCompleted()
        XCTAssertEqual(tracker.state.totalWorkouts, DemoWorkoutLibrary.details.count)
    }

    // MARK: - Equatable

    func testSyncStateEquality() {
        let a = SyncState(lastSyncDate: nil, totalWorkouts: 5, inProgress: false)
        let b = SyncState(lastSyncDate: nil, totalWorkouts: 5, inProgress: false)
        XCTAssertEqual(a, b)
    }

    func testSyncStateInequality() {
        let a = SyncState(totalWorkouts: 5)
        let b = SyncState(totalWorkouts: 10)
        XCTAssertNotEqual(a, b)
    }
}
