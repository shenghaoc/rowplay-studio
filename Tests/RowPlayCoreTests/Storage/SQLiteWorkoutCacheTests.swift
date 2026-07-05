import XCTest
@testable import RowPlayCore

final class SQLiteWorkoutCacheTests: XCTestCase {
    private var tempDir: URL!
    private var dbPath: String!
    private var cache: SQLiteWorkoutCache!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteWorkoutCacheTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("test.db").path
        cache = try! SQLiteWorkoutCache(path: dbPath)
    }

    override func tearDown() {
        cache = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Migration

    func testMigrationCreatesSchema() throws {
        try cache.migrate()

        let version = try cache.userVersion()
        XCTAssertEqual(version, 1)

        let workouts = try synchronousListWorkouts()
        XCTAssertTrue(workouts.isEmpty)
    }

    func testMigrationIsIdempotent() throws {
        try cache.migrate()
        try cache.migrate()

        let version = try cache.userVersion()
        XCTAssertEqual(version, 1)
    }

    // MARK: - Save and Load

    func testSaveAndLoadDetailRoundTrips() throws {
        try cache.migrate()

        let detail = DemoWorkoutLibrary.details.first!
        try synchronousSaveDetail(detail)

        let loaded = try synchronousLoadWorkout(id: detail.workout.id)

        XCTAssertNotNil(loaded)
        guard let loaded else { return XCTFail("loaded is nil") }
        XCTAssertEqual(loaded.workout.id, detail.workout.id)
        XCTAssertEqual(loaded.workout.sport, detail.workout.sport)
        XCTAssertEqual(loaded.workout.distance, detail.workout.distance, accuracy: 0.01)
        XCTAssertEqual(loaded.workout.time, detail.workout.time, accuracy: 0.01)
        XCTAssertEqual(loaded.workout.pace, detail.workout.pace, accuracy: 0.01)
        XCTAssertEqual(loaded.strokes.count, detail.strokes.count)
        XCTAssertEqual(loaded.splits.count, detail.splits.count)
    }

    func testSaveManyAndListWorkoutsSortsNewestFirst() throws {
        try cache.migrate()

        let details = DemoWorkoutLibrary.details
        for detail in details {
            try synchronousSaveDetail(detail)
        }

        let workouts = try synchronousListWorkouts()

        XCTAssertEqual(workouts.count, details.count)
        for i in 0..<(workouts.count - 1) {
            XCTAssertGreaterThanOrEqual(workouts[i].date, workouts[i + 1].date)
        }
    }

    // MARK: - Delete

    func testDeleteRemovesSingleWorkout() throws {
        try cache.migrate()

        let details = DemoWorkoutLibrary.details
        let first = details[0]
        let second = details[1]

        try synchronousSaveDetail(first)
        try synchronousSaveDetail(second)

        try synchronousDelete(id: first.workout.id)

        let loadedFirst = try synchronousLoadWorkout(id: first.workout.id)
        XCTAssertNil(loadedFirst)

        let loadedSecond = try synchronousLoadWorkout(id: second.workout.id)
        XCTAssertNotNil(loadedSecond)
        XCTAssertEqual(loadedSecond?.workout.id, second.workout.id)
    }

    func testDeleteAllClearsRows() throws {
        try cache.migrate()

        for detail in DemoWorkoutLibrary.details {
            try synchronousSaveDetail(detail)
        }

        try synchronousDeleteAll()

        let workouts = try synchronousListWorkouts()
        XCTAssertTrue(workouts.isEmpty)
    }

    // MARK: - Missing Data

    func testMissingDetailReturnsNil() throws {
        try cache.migrate()

        let loaded = try synchronousLoadWorkout(id: 999_999)
        XCTAssertNil(loaded)
    }

    // MARK: - Persistence

    func testCachePersistsAcrossInstances() throws {
        try cache.migrate()

        let detail = DemoWorkoutLibrary.details.first!
        try synchronousSaveDetail(detail)

        // Create a new instance pointing at the same database file.
        cache = nil
        let cache2 = try SQLiteWorkoutCache(path: dbPath)
        try cache2.migrate()

        let loaded = try synchronousLoadWorkoutFrom(cache2, id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.id, detail.workout.id)
        XCTAssertEqual(loaded?.strokes.count, detail.strokes.count)

        cache = cache2
    }

    // MARK: - Helpers

    /// Synchronous wrapper for async `saveDetail` to simplify XCTest.
    private func synchronousSaveDetail(_ detail: WorkoutDetail) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?
        Task {
            do {
                try await cache.saveDetail(detail)
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
    }

    /// Synchronous wrapper for async `loadWorkout`.
    private func synchronousLoadWorkout(id: Int) throws -> WorkoutDetail? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: WorkoutDetail?
        var thrownError: Error?
        Task {
            do {
                result = try await cache.loadWorkout(id: id)
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
        return result
    }

    /// Synchronous wrapper for async `loadWorkout` on a specific cache instance.
    private func synchronousLoadWorkoutFrom(_ cache: SQLiteWorkoutCache, id: Int) throws -> WorkoutDetail? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: WorkoutDetail?
        var thrownError: Error?
        Task {
            do {
                result = try await cache.loadWorkout(id: id)
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
        return result
    }

    /// Synchronous wrapper for async `listWorkouts` (via `loadAllWorkouts`).
    private func synchronousListWorkouts() throws -> [Workout] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Workout]?
        var thrownError: Error?
        Task {
            do {
                result = try await cache.listWorkouts()
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
        return result ?? []
    }

    /// Synchronous wrapper for async `delete(id:)`.
    private func synchronousDelete(id: Int) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?
        Task {
            do {
                try await cache.delete(id: id)
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
    }

    /// Synchronous wrapper for async `deleteAll`.
    private func synchronousDeleteAll() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?
        Task {
            do {
                try await cache.deleteAll()
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = thrownError { throw error }
    }
}
