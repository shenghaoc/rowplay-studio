import SQLite3
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

    func testMigrationCreatesSchema() async throws {
        try cache.migrate()

        let version = try cache.userVersion()
        XCTAssertEqual(version, 1)

        let workouts = try await cache.listWorkouts()
        XCTAssertTrue(workouts.isEmpty)
    }

    func testMigrationCreatesDateIndex() throws {
        try cache.migrate()

        let indexNames = try queryStrings("PRAGMA index_list(workouts);", column: 1)

        XCTAssertTrue(indexNames.contains("idx_workouts_date"))
    }

    func testMigrationIsIdempotent() throws {
        try cache.migrate()
        try cache.migrate()

        let version = try cache.userVersion()
        XCTAssertEqual(version, 1)
    }

    // MARK: - Save and Load

    func testSaveAndLoadDetailRoundTrips() async throws {
        try cache.migrate()

        let detail = DemoWorkoutLibrary.details.first!
        try await cache.save(detail: detail)

        let loaded = try await cache.detail(id: detail.workout.id)

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

    func testSaveManyAndListWorkoutsSortsNewestFirst() async throws {
        try cache.migrate()

        let details = DemoWorkoutLibrary.details
        try await cache.save(details: details)

        let workouts = try await cache.listWorkouts()

        XCTAssertEqual(workouts.count, details.count)
        for i in 0..<(workouts.count - 1) {
            XCTAssertGreaterThanOrEqual(workouts[i].date, workouts[i + 1].date)
        }
    }

    func testSaveWorkoutsPersistsSummaries() async throws {
        try cache.migrate()

        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)

        let loaded = try await cache.listWorkouts()

        XCTAssertEqual(loaded.count, workouts.count)
        for i in 0..<(loaded.count - 1) {
            XCTAssertGreaterThanOrEqual(loaded[i].date, loaded[i + 1].date)
        }
        XCTAssertTrue(workouts.allSatisfy { workout in
            loaded.contains(where: { $0.id == workout.id })
        })
    }

    func testSaveWorkoutsPreservesExistingDetailPayload() async throws {
        try cache.migrate()

        let detail = DemoWorkoutLibrary.details.first!
        try await cache.save(detail: detail)

        var updatedWorkout = detail.workout
        updatedWorkout.date = detail.workout.date.addingTimeInterval(60)
        updatedWorkout.comments = "Updated summary"
        try await cache.saveWorkouts([updatedWorkout])

        let loaded = try await cache.detail(id: detail.workout.id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.date, updatedWorkout.date)
        XCTAssertEqual(loaded?.workout.comments, updatedWorkout.comments)
        XCTAssertEqual(loaded?.strokes.count, detail.strokes.count)
        XCTAssertEqual(loaded?.splits.count, detail.splits.count)
    }

    func testListWorkoutsReadsSummaryColumnsWithoutDetailDecode() async throws {
        try cache.migrate()

        var workout = DemoWorkoutLibrary.details.first!.workout
        workout.strokeRate = 28
        workout.strokeCount = 240
        workout.heartRateAvg = 152
        workout.caloriesTotal = 108
        workout.wattMinutes = 96.5
        workout.dragFactor = 126
        workout.comments = "Summary from columns"
        workout.source = "Concept2 Online Logbook"
        workout.verified = false
        workout.hasStrokeData = true
        workout.isInterval = true
        let detail = WorkoutDetail(
            workout: workout,
            strokes: DemoWorkoutLibrary.details.first!.strokes,
            splits: DemoWorkoutLibrary.details.first!.splits
        )
        try await cache.save(detail: detail)
        try executeSQL("UPDATE workouts SET detail_json = 'not-json' WHERE id = \(workout.id);")

        let listed = try await cache.listWorkouts()
        let loaded = try XCTUnwrap(listed.first { $0.id == workout.id })

        XCTAssertEqual(loaded.sport, workout.sport)
        XCTAssertEqual(loaded.date, workout.date)
        XCTAssertEqual(loaded.distance, workout.distance, accuracy: 0.01)
        XCTAssertEqual(loaded.time, workout.time, accuracy: 0.01)
        XCTAssertEqual(loaded.pace, workout.pace, accuracy: 0.01)
        XCTAssertEqual(loaded.strokeRate, workout.strokeRate)
        XCTAssertEqual(loaded.strokeCount, workout.strokeCount)
        XCTAssertEqual(loaded.heartRateAvg, workout.heartRateAvg)
        XCTAssertEqual(loaded.caloriesTotal, workout.caloriesTotal)
        XCTAssertEqual(loaded.wattMinutes, workout.wattMinutes)
        XCTAssertEqual(loaded.dragFactor, workout.dragFactor)
        XCTAssertEqual(loaded.workoutType, workout.workoutType)
        XCTAssertEqual(loaded.comments, workout.comments)
        XCTAssertEqual(loaded.source, workout.source)
        XCTAssertEqual(loaded.verified, workout.verified)
        XCTAssertEqual(loaded.hasStrokeData, workout.hasStrokeData)
        XCTAssertEqual(loaded.isInterval, workout.isInterval)

        do {
            _ = try await cache.detail(id: workout.id)
            XCTFail("Expected corrupt detail JSON to throw")
        } catch WorkoutCacheError.decodingFailed {
            // Expected: full-detail reads still validate detail_json.
        } catch {
            XCTFail("Expected decodingFailed, got \(error)")
        }
    }

    // MARK: - Delete

    func testDeleteRemovesSingleWorkout() async throws {
        try cache.migrate()

        let details = DemoWorkoutLibrary.details
        let first = details[0]
        let second = details[1]

        try await cache.save(detail: first)
        try await cache.save(detail: second)

        try await cache.delete(id: first.workout.id)

        let loadedFirst = try await cache.detail(id: first.workout.id)
        XCTAssertNil(loadedFirst)

        let loadedSecond = try await cache.detail(id: second.workout.id)
        XCTAssertNotNil(loadedSecond)
        XCTAssertEqual(loadedSecond?.workout.id, second.workout.id)
    }

    func testDeleteAllClearsRows() async throws {
        try cache.migrate()

        try await cache.save(details: DemoWorkoutLibrary.details)

        try await cache.deleteAll()

        let workouts = try await cache.listWorkouts()
        XCTAssertTrue(workouts.isEmpty)
    }

    // MARK: - Missing Data

    func testMissingDetailReturnsNil() async throws {
        try cache.migrate()

        let loaded = try await cache.detail(id: 999_999)
        XCTAssertNil(loaded)
    }

    // MARK: - Persistence

    func testCachePersistsAcrossInstances() async throws {
        try cache.migrate()

        let detail = DemoWorkoutLibrary.details.first!
        try await cache.save(detail: detail)

        // Create a new instance pointing at the same database file.
        cache = nil
        let cache2 = try SQLiteWorkoutCache(path: dbPath)
        try cache2.migrate()

        let loaded = try await cache2.detail(id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.id, detail.workout.id)
        XCTAssertEqual(loaded?.strokes.count, detail.strokes.count)

        cache = cache2
    }

    // MARK: - Raw SQLite Helpers

    private func executeSQL(_ sql: String) throws {
        try withRawDatabase { db in
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw sqliteError("exec failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    private func queryStrings(_ sql: String, column: Int32) throws -> [String] {
        try withRawDatabase { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw sqliteError("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            }

            var values: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(stmt, column) else { continue }
                values.append(String(cString: cString))
            }
            return values
        }
    }

    private func withRawDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            throw sqliteError("open failed")
        }
        defer { sqlite3_close_v2(db) }

        return try body(db)
    }

    private func sqliteError(_ message: String) -> NSError {
        NSError(domain: "SQLiteWorkoutCacheTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
