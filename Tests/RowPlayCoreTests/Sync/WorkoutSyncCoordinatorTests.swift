import XCTest
@testable import RowPlayCore

// MARK: - Fake Clients and Caches

/// A Concept2APIClient that wraps another client and records all calls.
/// Can be configured to throw on fetchWorkouts or fetchWorkoutDetail.
private final class FakeConcept2Client: Concept2APIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetchWorkoutsCalls: [(page: Int, perPage: Int)] = []
    private var _fetchDetailIDs: [Int] = []

    var fetchWorkoutsHandler: ((Int, Int) async throws -> Concept2Page)?
    var fetchDetailHandler: ((Int) async throws -> WorkoutDetail)?

    var fetchWorkoutsCalls: [(page: Int, perPage: Int)] {
        lock.withLock { _fetchWorkoutsCalls }
    }

    var fetchDetailIDs: [Int] {
        lock.withLock { _fetchDetailIDs }
    }

    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        lock.withLock { _fetchWorkoutsCalls.append((page: page, perPage: perPage)) }
        if let handler = fetchWorkoutsHandler {
            return try await handler(page, perPage)
        }
        return Concept2Page(workouts: [], totalPages: 1)
    }

    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        lock.withLock { _fetchDetailIDs.append(id) }
        if let handler = fetchDetailHandler {
            return try await handler(id)
        }
        throw Concept2ClientError.workoutNotFound(id)
    }
}

/// A WorkoutCache that wraps another cache and can be configured to throw on save.
private final class FailingWorkoutCache: WorkoutCache, @unchecked Sendable {
    private let lock = NSLock()
    private var _savedDetails: [WorkoutDetail] = []
    var saveHandler: ((WorkoutDetail) async throws -> Void)?

    var savedDetails: [WorkoutDetail] {
        lock.withLock { _savedDetails }
    }

    func migrate() throws {}

    func save(detail: WorkoutDetail) async throws {
        lock.withLock { _savedDetails.append(detail) }
        if let handler = saveHandler {
            try await handler(detail)
        }
    }

    func save(details: [WorkoutDetail]) async throws {
        for detail in details {
            try await save(detail: detail)
        }
    }

    func saveWorkouts(_ workouts: [Workout]) async throws {}
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { nil }
    func listWorkouts() async throws -> [Workout] { [] }
    func delete(id: Workout.ID) async throws {}
    func deleteAll() async throws {}
}

/// A WorkoutCache that tracks whether migrate() was called.
private final class MigrateTrackingCache: WorkoutCache, @unchecked Sendable {
    private let lock = NSLock()
    private var _migrateCallCount = 0
    var migrateCallCount: Int { lock.withLock { _migrateCallCount } }

    func migrate() throws { lock.withLock { _migrateCallCount += 1 } }
    func save(detail: WorkoutDetail) async throws {}
    func save(details: [WorkoutDetail]) async throws {}
    func saveWorkouts(_ workouts: [Workout]) async throws {}
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { nil }
    func listWorkouts() async throws -> [Workout] { [] }
    func delete(id: Workout.ID) async throws {}
    func deleteAll() async throws {}
}

// MARK: - Tests

final class WorkoutSyncCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeDetail(id: Int) -> WorkoutDetail {
        WorkoutDetail(
            workout: Workout(
                id: id,
                date: Date(timeIntervalSince1970: TimeInterval(id * 1000)),
                sport: .rower,
                distance: 5000,
                time: 1200,
                pace: 120,
                workoutType: "JustRow",
                hasStrokeData: false
            ),
            strokes: [],
            splits: []
        )
    }

    // MARK: - testSyncAllFetchesAndSavesWorkoutDetails

    func testSyncAllFetchesAndSavesWorkoutDetails() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail1.workout, detail2.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            [detail1, detail2].first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.savedCount, 2)
        let cached1 = try await cache.detail(id: 1)
        let cached2 = try await cache.detail(id: 2)
        XCTAssertNotNil(cached1)
        XCTAssertNotNil(cached2)
        XCTAssertEqual(cached1?.workout.id, 1)
        XCTAssertEqual(cached2?.workout.id, 2)
    }

    // MARK: - testSyncAllReturnsCounts

    func testSyncAllReturnsCounts() async throws {
        let details = (1...5).map { makeDetail(id: $0) }

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: details.map(\.workout), totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            details.first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 5)
        XCTAssertEqual(result.savedCount, 5)
        XCTAssertEqual(result.failedCount, 0)
    }

    // MARK: - testSyncAllDoesNotUseRealNetwork

    func testSyncAllDoesNotUseRealNetwork() async throws {
        let detail = makeDetail(id: 42)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { _ in detail }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        _ = try await coordinator.syncAll()

        // Verify the fake client was called — no URLSession or real URL was used.
        XCTAssertEqual(client.fetchWorkoutsCalls.count, 1)
        XCTAssertEqual(client.fetchDetailIDs, [42])
    }

    // MARK: - testClientFailureThrowsSyncError

    func testClientFailureThrowsSyncError() async throws {
        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            throw Concept2Error.unauthorized
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected WorkoutSyncError.clientFailed")
        } catch let error as WorkoutSyncError {
            if case .clientFailed = error {
                // Expected
            } else {
                XCTFail("Expected clientFailed, got \(error)")
            }
        }
    }

    // MARK: - testCacheFailureIncrementsFailedCount

    func testCacheFailureIncrementsFailedCount() async throws {
        let detail = makeDetail(id: 1)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { _ in detail }

        let cache = FailingWorkoutCache()
        cache.saveHandler = { _ in
            throw WorkoutCacheError.queryFailed("disk full")
        }

        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)
        let result = try await coordinator.syncAll()

        // Per-workout cache failures increment failedCount rather than throwing.
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
    }

    // MARK: - testDetailFetchFailureIncrementsFailedCount

    func testDetailFetchFailureIncrementsFailedCount() async throws {
        let detail = makeDetail(id: 1)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail.workout], totalPages: 1)
        }
        // Simulate a client-side mapping failure by throwing a decoding error.
        client.fetchDetailHandler = { _ in
            throw Concept2Error.decodingFailed
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        // Decoding failures are per-workout failures, not fundamental.
        XCTAssertEqual(result.fetchedCount, 1)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
    }

    // MARK: - testSyncIsIdempotentForSameWorkoutIDs

    func testSyncIsIdempotentForSameWorkoutIDs() async throws {
        let details = (1...3).map { makeDetail(id: $0) }

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: details.map(\.workout), totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            details.first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        // First sync
        let result1 = try await coordinator.syncAll()
        XCTAssertEqual(result1.savedCount, 3)

        // Second sync with same data
        let result2 = try await coordinator.syncAll()
        XCTAssertEqual(result2.savedCount, 3)

        // Cache should still have exactly 3 workouts (no duplicates).
        let workouts = try await cache.listWorkouts()
        XCTAssertEqual(workouts.count, 3)
    }

    // MARK: - testErrorsDoNotExposeToken

    func testErrorsDoNotExposeToken() async throws {
        let secretToken = "test-secret-token-abc123"

        // Use a custom error whose description contains the token,
        // so we can verify that redact() strips it before it reaches
        // the WorkoutSyncError description.
        struct LeakyError: Error, CustomStringConvertible {
            let token: String
            var description: String { "Auth failed with token=\(token)" }
        }

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            throw LeakyError(token: secretToken)
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected error")
        } catch let error as WorkoutSyncError {
            let description = error.description
            XCTAssertFalse(description.contains(secretToken),
                "Error description must not contain the token string")
        }
    }

    // MARK: - testSyncAllWithNoWorkoutsReturnsZeroCounts

    func testSyncAllWithNoWorkoutsReturnsZeroCounts() async throws {
        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [], totalPages: 1)
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 0)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
    }

    // MARK: - testTimestampsArePopulated

    func testTimestampsArePopulated() async throws {
        let detail = makeDetail(id: 1)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { _ in detail }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertLessThanOrEqual(result.startedAt, result.finishedAt)
        // finishedAt should be very close to now (within 5 seconds).
        let now = Date()
        XCTAssertLessThanOrEqual(result.finishedAt, now)
    }

    // MARK: - testPartialFailureContinuesSync

    func testPartialFailureContinuesSync() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)
        let detail3 = makeDetail(id: 3)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(
                workouts: [detail1.workout, detail2.workout, detail3.workout],
                totalPages: 1
            )
        }
        // Workout 2 fails to fetch detail.
        client.fetchDetailHandler = { id in
            if id == 2 { throw Concept2ClientError.workoutNotFound(2) }
            return [detail1, detail3].first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 3)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(result.failedCount, 1)

        // Verify the successful workouts are in the cache.
        let cached1 = try await cache.detail(id: 1)
        let cached2 = try await cache.detail(id: 2)
        let cached3 = try await cache.detail(id: 3)
        XCTAssertNotNil(cached1)
        XCTAssertNil(cached2)
        XCTAssertNotNil(cached3)
    }

    // MARK: - testAuthErrorAbortsSync

    func testAuthErrorAbortsSync() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)
        let detail3 = makeDetail(id: 3)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(
                workouts: [detail1.workout, detail2.workout, detail3.workout],
                totalPages: 1
            )
        }
        // Workout 1 fails with an auth error — sync should abort immediately.
        client.fetchDetailHandler = { id in
            if id == 1 { throw Concept2ClientError.notAuthenticated }
            return [detail2, detail3].first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected WorkoutSyncError.clientFailed for auth error")
        } catch let error as WorkoutSyncError {
            if case .clientFailed = error {
                // Expected — sync aborted early due to auth failure.
            } else {
                XCTFail("Expected clientFailed, got \(error)")
            }
        }

        // Only workout 1 was attempted before the auth error aborted the loop.
        XCTAssertEqual(client.fetchDetailIDs, [1])
    }

    // MARK: - testForbiddenErrorAbortsSync

    func testForbiddenErrorAbortsSync() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail1.workout, detail2.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            if id == 1 { throw Concept2Error.forbidden }
            return detail2
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected WorkoutSyncError.clientFailed for forbidden error")
        } catch let error as WorkoutSyncError {
            if case .clientFailed = error {
                // Expected
            } else {
                XCTFail("Expected clientFailed, got \(error)")
            }
        }

        XCTAssertEqual(client.fetchDetailIDs, [1])
    }

    // MARK: - testRateLimitAbortsSync

    func testRateLimitAbortsSync() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail1.workout, detail2.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            if id == 1 { throw Concept2Error.rateLimited }
            return detail2
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected WorkoutSyncError.clientFailed for rate-limit error")
        } catch let error as WorkoutSyncError {
            if case .clientFailed = error {
                // Expected
            } else {
                XCTFail("Expected clientFailed, got \(error)")
            }
        }

        XCTAssertEqual(client.fetchDetailIDs, [1])
    }

    // MARK: - testMultiPageSync

    func testMultiPageSync() async throws {
        let details = (1...10).map { makeDetail(id: $0) }
        var callCount = 0

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { page, perPage in
            callCount += 1
            let all = details.map(\.workout)
            let perPage = 5
            let totalPages = 2
            let start = (page - 1) * perPage
            let end = min(start + perPage, all.count)
            guard start < all.count else {
                return Concept2Page(workouts: [], totalPages: totalPages)
            }
            return Concept2Page(
                workouts: Array(all[start..<end]),
                totalPages: totalPages
            )
        }
        client.fetchDetailHandler = { id in
            details.first { $0.workout.id == id }!
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache, perPage: 5)

        let result = try await coordinator.syncAll()

        XCTAssertEqual(result.fetchedCount, 10)
        XCTAssertEqual(result.savedCount, 10)
        XCTAssertEqual(result.failedCount, 0)
        // Should have fetched 2 pages.
        XCTAssertEqual(client.fetchWorkoutsCalls.count, 2)
    }

    // MARK: - testCancellationPropagatesFromDetailFetch

    func testCancellationPropagatesFromDetailFetch() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail1.workout, detail2.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { id in
            if id == 1 { throw CancellationError() }
            return detail2
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected CancellationError to propagate")
        } catch is CancellationError {
            // Expected — cancellation should propagate, not be swallowed.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - testCancellationPropagatesFromCacheSave

    func testCancellationPropagatesFromCacheSave() async throws {
        let detail = makeDetail(id: 1)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail.workout], totalPages: 1)
        }
        client.fetchDetailHandler = { _ in detail }

        let cache = FailingWorkoutCache()
        cache.saveHandler = { _ in throw CancellationError() }

        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected CancellationError to propagate")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - testHTTP401ViaClientErrorAbortsSync

    func testHTTP401ViaClientErrorAbortsSync() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)

        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [detail1.workout, detail2.workout], totalPages: 1)
        }
        // Concept2ClientError.httpError(statusCode: 401) should also trigger abort.
        client.fetchDetailHandler = { id in
            if id == 1 { throw Concept2ClientError.httpError(statusCode: 401) }
            return detail2
        }

        let cache = InMemoryWorkoutCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        do {
            _ = try await coordinator.syncAll()
            XCTFail("Expected WorkoutSyncError.clientFailed for HTTP 401")
        } catch let error as WorkoutSyncError {
            if case .clientFailed = error {
                // Expected
            } else {
                XCTFail("Expected clientFailed, got \(error)")
            }
        }

        XCTAssertEqual(client.fetchDetailIDs, [1])
    }

    // MARK: - testSyncErrorDescriptionRedactsDetails

    func testSyncErrorDescriptionRedactsDetails() async throws {
        let secretToken = "abcdef0123456789abcdef0123456789abcdef01" // 40-char hex, matches token regex

        // Construct an error whose detail string contains a token-like value.
        let error = WorkoutSyncError.clientFailed("Got token=\(secretToken)")
        let description = error.description

        XCTAssertFalse(description.contains(secretToken),
            "WorkoutSyncError.description must redact sensitive details")
        XCTAssertTrue(description.contains("[REDACTED]"),
            "Redacted content should be replaced with [REDACTED]")
    }

    // MARK: - testMigrateCalledBeforeSync

    func testMigrateCalledBeforeSync() async throws {
        let client = FakeConcept2Client()
        client.fetchWorkoutsHandler = { _, _ in
            Concept2Page(workouts: [], totalPages: 1)
        }

        let cache = MigrateTrackingCache()
        let coordinator = WorkoutSyncCoordinator(client: client, cache: cache)

        _ = try await coordinator.syncAll()

        XCTAssertEqual(cache.migrateCallCount, 1,
            "migrate() should be called once at the start of syncAll()")
    }
}
