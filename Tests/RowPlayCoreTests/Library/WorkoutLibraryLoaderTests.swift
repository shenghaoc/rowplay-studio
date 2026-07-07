import XCTest
@testable import RowPlayCore

final class WorkoutLibraryLoaderTests: XCTestCase {
    // MARK: - testLoadsCachedWorkoutsWhenCacheHasData

    func testLoadsCachedWorkoutsWhenCacheHasData() async throws {
        let cachedDetail = makeDetail(id: 42)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: cachedDetail)

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 1)
        XCTAssertEqual(snapshot.details.first?.workout.id, 42)
    }

    // MARK: - testLoadsDemoWhenCacheEmptyAndDemoEnabled

    func testLoadsDemoWhenCacheEmptyAndDemoEnabled() async throws {
        let cache = InMemoryWorkoutCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .demo)
        XCTAssertEqual(snapshot.details.count, DemoWorkoutLibrary.details.count)
    }

    // MARK: - testReturnsEmptyWhenCacheEmptyAndDemoDisabled

    func testReturnsEmptyWhenCacheEmptyAndDemoDisabled() async throws {
        let cache = InMemoryWorkoutCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .empty)
        XCTAssertTrue(snapshot.details.isEmpty)
    }

    // MARK: - testCacheTakesPriorityOverDemo

    func testCacheTakesPriorityOverDemo() async throws {
        let cachedDetail = makeDetail(id: 99)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: cachedDetail)

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 1)
        XCTAssertEqual(snapshot.details.first?.workout.id, 99)
    }

    // MARK: - testCacheFailureDoesNotSilentlyShowDemo

    func testCacheFailureDoesNotSilentlyShowDemo() async {
        let cache = ThrowingWorkoutCache()

        do {
            _ = try await WorkoutLibraryLoader.load(
                cache: cache,
                demoModeEnabled: true
            )
            XCTFail("Expected error to be thrown")
        } catch {
            // Error propagated — no silent fallback to demo data.
            XCTAssertTrue(error is TestCacheError)
        }
    }

    // MARK: - testSnapshotSourceIsStable

    func testSnapshotSourceIsStable() async throws {
        let cache = InMemoryWorkoutCache()

        let emptySnapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )
        XCTAssertEqual(emptySnapshot.source, .empty)

        let demoSnapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )
        XCTAssertEqual(demoSnapshot.source, .demo)

        try await cache.save(detail: makeDetail(id: 1))
        let cacheSnapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )
        XCTAssertEqual(cacheSnapshot.source, .cache)
    }

    // MARK: - Helpers

    private func makeDetail(id: Int) -> WorkoutDetail {
        WorkoutDetail(
            workout: Workout(
                id: id,
                date: Date(timeIntervalSince1970: TimeInterval(id)),
                sport: .rower,
                distance: 2_000,
                time: 480,
                pace: 120,
                workoutType: "Test",
                hasStrokeData: false
            ),
            strokes: [],
            splits: []
        )
    }
}

// MARK: - Test Helpers

private enum TestCacheError: Error {
    case intentional
}

/// A WorkoutCache that throws on every operation for error-propagation testing.
private final class ThrowingWorkoutCache: WorkoutCache, @unchecked Sendable {
    func migrate() throws { throw TestCacheError.intentional }
    func save(detail: WorkoutDetail) async throws { throw TestCacheError.intentional }
    func save(details: [WorkoutDetail]) async throws { throw TestCacheError.intentional }
    func saveWorkouts(_ workouts: [Workout]) async throws { throw TestCacheError.intentional }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { throw TestCacheError.intentional }
    func listWorkouts() async throws -> [Workout] { throw TestCacheError.intentional }
    func delete(id: Workout.ID) async throws { throw TestCacheError.intentional }
    func deleteAll() async throws { throw TestCacheError.intentional }
}
