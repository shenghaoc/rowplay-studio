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
}
