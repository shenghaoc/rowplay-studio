import XCTest
import Synchronization
@testable import RowPlayCore

final class WorkoutLibraryLoaderTests: XCTestCase {
    // MARK: - Cache → Demo → Empty Fallback

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

    func testLoadsDemoWhenCacheEmptyAndDemoEnabled() async throws {
        let cache = InMemoryWorkoutCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: true
        )

        XCTAssertEqual(snapshot.source, .demo)
        XCTAssertEqual(snapshot.details.count, DemoWorkoutLibrary.details.count)
    }

    func testReturnsEmptyWhenCacheEmptyAndDemoDisabled() async throws {
        let cache = InMemoryWorkoutCache()

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .empty)
        XCTAssertTrue(snapshot.details.isEmpty)
    }

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

    // MARK: - Error Propagation

    func testCacheFailureDoesNotSilentlyShowDemo() async {
        let cache = ThrowingWorkoutCache()

        do {
            _ = try await WorkoutLibraryLoader.load(
                cache: cache,
                demoModeEnabled: true
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestCacheError)
        }
    }

    func testCacheFailureLeavesSourceUnchanged() async {
        let cache = ThrowingWorkoutCache()

        do {
            _ = try await WorkoutLibraryLoader.load(
                cache: cache,
                demoModeEnabled: false
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestCacheError)
        }
    }

    // MARK: - Source Stability

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

    // MARK: - Placeholder Detail Fallback

    func testMissingDetailProducesPlaceholderWithEmptyStrokesAndSplits() async throws {
        // Use a cache where listWorkouts() returns a workout but detail(id:) returns nil.
        // InMemoryWorkoutCache.saveWorkouts creates placeholder details, so we use a
        // custom cache that only stores summaries.
        let cache = SummaryOnlyCache()
        let workout = makeDetail(id: 55).workout
        try await cache.saveWorkouts([workout])

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details.count, 1)
        XCTAssertEqual(snapshot.details.first?.workout.id, 55)
        XCTAssertTrue(snapshot.details.first?.strokes.isEmpty ?? false)
        XCTAssertTrue(snapshot.details.first?.splits.isEmpty ?? false)
    }

    func testMultipleWorkoutsSomeWithMissingDetails() async throws {
        let cache = SummaryOnlyCache()
        let workout1 = makeDetail(id: 1).workout
        let workout2 = makeDetail(id: 2).workout
        try await cache.saveWorkouts([workout1, workout2])

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.details.count, 2)
        for detail in snapshot.details {
            XCTAssertTrue(detail.strokes.isEmpty)
            XCTAssertTrue(detail.splits.isEmpty)
        }
    }

    func testUsesBatchDetailLookup() async throws {
        let detail1 = makeDetail(id: 1)
        let detail2 = makeDetail(id: 2)
        let cache = BatchOnlyCache(details: [detail1, detail2])

        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )

        XCTAssertEqual(snapshot.source, .cache)
        XCTAssertEqual(snapshot.details, [detail2, detail1])
        XCTAssertEqual(cache.batchLookupCount, 1)
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

/// A WorkoutCache that stores only summaries (no detail JSON), so `detail(id:)` always
/// returns nil for workouts saved via `saveWorkouts`. Used to test the loader's
/// placeholder fallback path.
private final class SummaryOnlyCache: WorkoutCache {
    private let workouts = Mutex([Int: Workout]())

    func migrate() throws {}

    func save(detail: WorkoutDetail) async throws {
        workouts.withLock {
            $0[detail.workout.id] = detail.workout
        }
    }

    func save(details: [WorkoutDetail]) async throws {
        workouts.withLock { workouts in
            for detail in details {
                workouts[detail.workout.id] = detail.workout
            }
        }
    }

    func saveWorkouts(_ workouts: [Workout]) async throws {
        self.workouts.withLock { storedWorkouts in
            for workout in workouts {
                storedWorkouts[workout.id] = workout
            }
        }
    }

    func listWorkouts() async throws -> [Workout] {
        workouts.withLock {
            $0.values.sorted { $0.date > $1.date }
        }
    }

    func detail(id: Workout.ID) async throws -> WorkoutDetail? {
        // Always return nil to simulate missing detail data.
        nil
    }

    func delete(id: Workout.ID) async throws {
        workouts.withLock { $0[id] = nil }
    }

    func deleteAll() async throws {
        workouts.withLock { $0.removeAll() }
    }
}

private final class BatchOnlyCache: WorkoutCache {
    private let storedDetails: [Workout.ID: WorkoutDetail]
    private let batchLookupCountState = Mutex(0)

    init(details: [WorkoutDetail]) {
        storedDetails = Dictionary(uniqueKeysWithValues: details.map { ($0.workout.id, $0) })
    }

    var batchLookupCount: Int {
        batchLookupCountState.withLock { $0 }
    }

    func migrate() throws {}
    func save(detail: WorkoutDetail) async throws {}
    func save(details: [WorkoutDetail]) async throws {}
    func saveWorkouts(_ workouts: [Workout]) async throws {}

    func listWorkouts() async throws -> [Workout] {
        storedDetails.values.map(\.workout).sorted { $0.date > $1.date }
    }

    func details(for ids: [Workout.ID]) async throws -> [Workout.ID: WorkoutDetail] {
        batchLookupCountState.withLock { $0 += 1 }
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            storedDetails[id].map { (id, $0) }
        })
    }

    func detail(id: Workout.ID) async throws -> WorkoutDetail? {
        XCTFail("WorkoutLibraryLoader should use details(for:) instead of detail(id:)")
        return storedDetails[id]
    }

    func delete(id: Workout.ID) async throws {}
    func deleteAll() async throws {}
}
