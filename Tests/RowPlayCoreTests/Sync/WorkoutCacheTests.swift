import XCTest
@testable import RowPlayCore

final class WorkoutCacheTests: XCTestCase {
    private var cache: InMemoryWorkoutCache!

    override func setUp() {
        super.setUp()
        cache = InMemoryWorkoutCache()
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    // MARK: - saveWorkouts / loadAllWorkouts

    func testSaveAndLoadWorkouts() async throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, workouts.count)
    }

    func testLoadAllReturnsSortedByDateDescending() async throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        let loaded = try await cache.loadAllWorkouts()
        let dates = loaded.map(\.date)
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1])
        }
    }

    func testLoadAllFromEmptyCache() async throws {
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveWorkoutsUpserts() async throws {
        let workout = DemoWorkoutLibrary.details[0].workout
        try await cache.saveWorkouts([workout])
        try await cache.saveWorkouts([workout]) // Same ID, should not duplicate
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, 1)
    }

    // MARK: - saveDetail / loadWorkout

    func testSaveAndLoadDetail() async throws {
        let detail = DemoWorkoutLibrary.details[0]
        try await cache.saveDetail(detail)
        let loaded = try await cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.id, detail.workout.id)
        XCTAssertEqual(loaded?.strokes.count, detail.strokes.count)
        XCTAssertEqual(loaded?.splits.count, detail.splits.count)
    }

    func testLoadDetailMissingID() async throws {
        let loaded = try await cache.loadWorkout(id: 99999)
        XCTAssertNil(loaded)
    }

    func testSaveDetailAlsoUpsertsWorkoutSummary() async throws {
        let detail = DemoWorkoutLibrary.details[0]
        try await cache.saveDetail(detail)
        let summaries = try await cache.loadAllWorkouts()
        XCTAssertTrue(summaries.contains(where: { $0.id == detail.workout.id }))
    }

    func testSaveWorkoutsUpdatesExistingDetailSummary() async throws {
        let detail = DemoWorkoutLibrary.details[0]
        try await cache.saveDetail(detail)
        // Save an updated summary with a different date.
        var updatedWorkout = detail.workout
        updatedWorkout.date = Date(timeIntervalSince1970: 0)
        try await cache.saveWorkouts([updatedWorkout])
        let loaded = try await cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.date, updatedWorkout.date,
            "saveWorkouts should update the embedded workout in cached details")
    }

    // MARK: - deleteAll

    func testDeleteAllClearsWorkouts() async throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        try await cache.deleteAll()
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteAllClearsDetails() async throws {
        let detail = DemoWorkoutLibrary.details[0]
        try await cache.saveDetail(detail)
        try await cache.deleteAll()
        let loaded = try await cache.loadWorkout(id: detail.workout.id)
        XCTAssertNil(loaded)
    }

    func testDeleteAllOnEmptyCacheIsIdempotent() async throws {
        try await cache.deleteAll() // Should not throw
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteAllThenSave() async throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try await cache.saveWorkouts(workouts)
        try await cache.deleteAll()
        try await cache.saveWorkouts([workouts[0]])
        let loaded = try await cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, workouts[0].id)
    }

    // MARK: - Protocol conformance

    func testWorkoutCacheProtocolConformance() async throws {
        let cache: WorkoutCache = InMemoryWorkoutCache()
        let detail = DemoWorkoutLibrary.details[0]
        try await cache.saveDetail(detail)
        let loaded = try await cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
    }
}
