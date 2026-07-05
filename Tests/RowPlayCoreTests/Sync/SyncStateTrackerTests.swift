import XCTest
@testable import RowPlayCore

/// A WorkoutCache that throws on every operation, for testing error paths.
private final class ThrowingWorkoutCache: WorkoutCache, @unchecked Sendable {
    func migrate() throws { throw NSError(domain: "test", code: 1) }
    func save(detail: WorkoutDetail) async throws { throw NSError(domain: "test", code: 1) }
    func save(details: [WorkoutDetail]) async throws { throw NSError(domain: "test", code: 1) }
    func saveWorkouts(_ workouts: [Workout]) async throws { throw NSError(domain: "test", code: 1) }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { throw NSError(domain: "test", code: 1) }
    func listWorkouts() async throws -> [Workout] { throw NSError(domain: "test", code: 1) }
    func delete(id: Workout.ID) async throws { throw NSError(domain: "test", code: 1) }
    func deleteAll() async throws { throw NSError(domain: "test", code: 1) }
}

@available(macOS 14.0, *)
@MainActor
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

    func testRefreshesInitialWorkoutCountFromCache() async throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        let freshTracker = SyncStateTracker(cache: cache)
        await freshTracker.refreshWorkoutCount()
        XCTAssertEqual(freshTracker.state.totalWorkouts, workouts.count)
    }

    // MARK: - Sync lifecycle

    func testSyncStarted() {
        tracker.syncStarted()
        XCTAssertTrue(tracker.state.inProgress)
        XCTAssertNil(tracker.state.lastError)
        XCTAssertNil(tracker.state.lastErrorDate)
    }

    func testSyncCompleted() async {
        tracker.syncStarted()
        await tracker.syncCompleted()
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastSyncDate)
        XCTAssertNil(tracker.state.lastError)
    }

    func testSyncFailed() async {
        tracker.syncStarted()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])
        await tracker.syncFailed(error: error)
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastError)
        XCTAssertNotNil(tracker.state.lastErrorDate)
        XCTAssertNil(tracker.state.lastSyncDate)
    }

    func testSyncFailedRedactsError() async {
        tracker.syncStarted()
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Authorization: Bearer abcdef1234567890abcdef1234567890"
        ])
        await tracker.syncFailed(error: error)
        XCTAssertNotNil(tracker.state.lastError)
        // The error should be redacted — should not contain the token.
        XCTAssertFalse(tracker.state.lastError?.contains("abcdef1234567890abcdef1234567890") ?? false)
        XCTAssertTrue(tracker.state.lastError?.contains("[REDACTED]") ?? false)
    }

    // MARK: - State transitions

    func testRetryAfterError() async {
        tracker.syncStarted()
        await tracker.syncFailed(error: NSError(domain: "test", code: 1))
        // Retry
        tracker.syncStarted()
        XCTAssertNil(tracker.state.lastError)
        XCTAssertTrue(tracker.state.inProgress)

        await tracker.syncCompleted()
        XCTAssertFalse(tracker.state.inProgress)
        XCTAssertNotNil(tracker.state.lastSyncDate)
        XCTAssertNil(tracker.state.lastError)
    }

    func testRefreshWorkoutCount() async throws {
        XCTAssertEqual(tracker.state.totalWorkouts, 0)
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        await tracker.refreshWorkoutCount()
        XCTAssertEqual(tracker.state.totalWorkouts, workouts.count)
    }

    func testSyncCompletedRefreshesWorkoutCount() async throws {
        try await cache.saveWorkouts([DemoWorkoutLibrary.details[0].workout])
        tracker.syncStarted()
        try await cache.saveWorkouts(DemoWorkoutLibrary.details.map(\.workout))
        await tracker.syncCompleted()
        XCTAssertEqual(tracker.state.totalWorkouts, DemoWorkoutLibrary.details.count)
    }

    // MARK: - Error handling

    func testRefreshWorkoutCountHandlesCacheError() async {
        let throwingCache = ThrowingWorkoutCache()
        let errorTracker = SyncStateTracker(cache: throwingCache)
        await errorTracker.refreshWorkoutCount()
        // Should not crash; totalWorkouts stays at 0.
        XCTAssertEqual(errorTracker.state.totalWorkouts, 0)
    }

    func testSyncFailedRefreshesWorkoutCount() async throws {
        try await cache.saveWorkouts([DemoWorkoutLibrary.details[0].workout])
        tracker.syncStarted()
        try await cache.saveWorkouts(DemoWorkoutLibrary.details.map(\.workout))
        let error = NSError(domain: "test", code: 1)
        await tracker.syncFailed(error: error)
        XCTAssertEqual(tracker.state.totalWorkouts, DemoWorkoutLibrary.details.count,
            "syncFailed should refresh workout count from cache")
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
