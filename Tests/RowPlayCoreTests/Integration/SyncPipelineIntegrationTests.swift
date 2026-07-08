import Foundation
import XCTest
@testable import RowPlayCore

// MARK: - Fakes

/// A Concept2APIClient that always throws on fetchWorkouts.
private final class FailingConcept2Client: Concept2APIClient, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        throw error
    }

    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        throw error
    }
}

/// A Concept2APIClient that fails `fetchWorkoutDetail` for specific workout IDs.
private final class SelectiveFailureClient: Concept2APIClient, @unchecked Sendable {
    private let details: [WorkoutDetail]
    private let failingIDs: Set<Int>

    init(details: [WorkoutDetail], failingIDs: Set<Int>) {
        self.details = details
        self.failingIDs = failingIDs
    }

    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        let workouts = details.map(\.workout)
        return Concept2Page(workouts: workouts, totalPages: 1)
    }

    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        if failingIDs.contains(id) {
            throw Concept2ClientError.workoutNotFound(id)
        }
        guard let detail = details.first(where: { $0.workout.id == id }) else {
            throw Concept2ClientError.workoutNotFound(id)
        }
        return detail
    }
}

// MARK: - Tests

final class SyncPipelineIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncPipelineIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeTempCache() throws -> (SQLiteWorkoutCache, String) {
        let dbPath = tempDir.appendingPathComponent("\(UUID().uuidString).db").path
        let cache = try SQLiteWorkoutCache(path: dbPath)
        try cache.migrate()
        return (cache, dbPath)
    }

    /// Build a minimal WorkoutDetail for integration testing.
    private func makeTestDetail(id: Int, sport: Sport = .rower) -> WorkoutDetail {
        let workout = Workout(
            id: id,
            date: Date(timeIntervalSince1970: TimeInterval(id * 100_000)),
            sport: sport,
            distance: 2_000,
            time: 480,
            pace: 120,
            workoutType: "Test \(id)",
            hasStrokeData: false
        )
        return WorkoutDetail(workout: workout, strokes: [], splits: [])
    }

    // MARK: - 1. Pipeline writes cache and library loads cache

    func testSyncPipelineWritesCacheAndLibraryLoadsCache() async throws {
        let (cache, _) = try makeTempCache()
        // Use real demo details so stroke/split data round-trips through SQLite.
        let demoDetails = Array(DemoWorkoutLibrary.details.prefix(2))
        let client = MockConcept2Client(details: demoDetails)
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 2)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(result.failedCount, 0)

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 2)

        // Verify stroke and split data survived the JSON→SQLite→JSON round-trip.
        for original in demoDetails {
            let loaded = try XCTUnwrap(
                snapshot.details.first(where: { $0.workout.id == original.workout.id })
            )
            XCTAssertEqual(loaded.strokes.count, original.strokes.count)
            XCTAssertEqual(loaded.splits.count, original.splits.count)
            if let firstStroke = loaded.strokes.first,
               let originalStroke = original.strokes.first {
                XCTAssertEqual(firstStroke.t, originalStroke.t, accuracy: 0.001)
                XCTAssertEqual(firstStroke.pace, originalStroke.pace, accuracy: 0.001)
            }
        }
    }

    // MARK: - 2. Pipeline works with demo mode disabled

    func testSyncPipelineWorksWithDemoModeDisabled() async throws {
        let (cache, _) = try makeTempCache()
        let detail = makeTestDetail(id: 6001)
        let client = MockConcept2Client(details: [detail])
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        _ = try await coordinator.syncAll()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 1)
        XCTAssertEqual(snapshot.details.first?.workout.id, 6001)
    }

    // MARK: - 3. Empty cache with demo mode disabled returns empty

    func testEmptyCacheDemoModeDisabledReturnsEmpty() async throws {
        let (cache, _) = try makeTempCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .empty)
        XCTAssertTrue(snapshot.details.isEmpty)
    }

    // MARK: - 4. Empty cache with demo mode enabled returns demo

    func testEmptyCacheDemoModeEnabledReturnsDemo() async throws {
        let (cache, _) = try makeTempCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .demo)
        XCTAssertEqual(snapshot.details.count, DemoWorkoutLibrary.details.count)
    }

    // MARK: - 5. Repeated sync does not duplicate workouts

    func testRepeatedSyncDoesNotDuplicateWorkouts() async throws {
        let (cache, _) = try makeTempCache()
        let detail1 = makeTestDetail(id: 7001)
        let detail2 = makeTestDetail(id: 7002)
        let client = MockConcept2Client(details: [detail1, detail2])
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        _ = try await coordinator.syncAll()
        _ = try await coordinator.syncAll()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.details.count, 2)
        let ids = snapshot.details.map(\.workout.id)
        XCTAssertEqual(Set(ids).count, ids.count, "All workout IDs should be unique")
    }

    // MARK: - 6. Pipeline persists across cache instances

    func testPipelinePersistsAcrossCacheInstances() async throws {
        let dbPath: String
        do {
            let (cacheA, path) = try makeTempCache()
            dbPath = path
            let detail1 = makeTestDetail(id: 8001)
            let detail2 = makeTestDetail(id: 8002)
            let client = MockConcept2Client(details: [detail1, detail2])
            let coordinator = WorkoutSyncCoordinator(client: client, cache: cacheA)
            _ = try await coordinator.syncAll()
        }

        // Open a new instance on the same DB file after cacheA is deallocated.
        let cacheB = try SQLiteWorkoutCache(path: dbPath)
        try cacheB.migrate()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cacheB,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 2)
        let ids = Set(snapshot.details.map(\.workout.id))
        XCTAssertTrue(ids.contains(8001))
        XCTAssertTrue(ids.contains(8002))
    }

    // MARK: - 7. Client failure does not replace cache with demo

    func testClientFailureDoesNotReplaceCacheWithDemo() async throws {
        let (cache, _) = try makeTempCache()

        // Seed the cache with one workout before the failing sync.
        let seededDetail = makeTestDetail(id: 9001)
        try await cache.save(detail: seededDetail)

        // Sync with a client that always throws.
        let failingClient = FailingConcept2Client(
            error: Concept2ClientError.httpError(statusCode: 500)
        )
        let coordinator = WorkoutSyncCoordinator(client: failingClient, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected syncAll to throw")
        } catch let error as WorkoutSyncError {
            // Expected: the summary fetch fails.
            _ = error
        } catch {
            XCTFail("Expected WorkoutSyncError, but got: \(error)")
        }

        // Load library with demo mode enabled — cached data should still be returned.
        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 1)
        XCTAssertEqual(snapshot.details.first?.workout.id, 9001)
    }

    // MARK: - 8. Partial failure continues with real SQLite cache

    func testPartialFailureContinuesSyncWithRealSQLite() async throws {
        let (cache, _) = try makeTempCache()
        let detail1 = makeTestDetail(id: 10_001)
        let detail2 = makeTestDetail(id: 10_002)
        let detail3 = makeTestDetail(id: 10_003)

        // Client fails detail fetch for workout 2 only.
        let client = SelectiveFailureClient(
            details: [detail1, detail2, detail3],
            failingIDs: [10_002]
        )
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 3)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(result.failedCount, 1)

        // Verify only the successful workouts are in the SQLite cache.
        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 2)
        let ids = Set(snapshot.details.map(\.workout.id))
        XCTAssertTrue(ids.contains(10_001))
        XCTAssertTrue(ids.contains(10_003))
        XCTAssertFalse(ids.contains(10_002))
    }

    // MARK: - 9. WorkoutSyncError.description redacts secrets

    func testWorkoutSyncErrorDescriptionRedactsSecrets() {
        let secret = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let error = WorkoutSyncError.clientFailed("token: \(secret)")
        let description = error.description
        XCTAssertFalse(
            description.contains(secret),
            "WorkoutSyncError.description must redact secrets independently"
        )
    }
}
