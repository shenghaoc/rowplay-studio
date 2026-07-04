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

    func testSaveAndLoadWorkouts() throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        let loaded = try cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, workouts.count)
    }

    func testLoadAllReturnsSortedByDateDescending() throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        let loaded = try cache.loadAllWorkouts()
        let dates = loaded.map(\.date)
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1])
        }
    }

    func testLoadAllFromEmptyCache() throws {
        let loaded = try cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveWorkoutsUpserts() throws {
        let workout = DemoWorkoutLibrary.details[0].workout
        try cache.saveWorkouts([workout])
        try cache.saveWorkouts([workout]) // Same ID, should not duplicate
        let loaded = try cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, 1)
    }

    // MARK: - saveDetail / loadWorkout

    func testSaveAndLoadDetail() throws {
        let detail = DemoWorkoutLibrary.details[0]
        try cache.saveDetail(detail)
        let loaded = try cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.id, detail.workout.id)
        XCTAssertEqual(loaded?.strokes.count, detail.strokes.count)
        XCTAssertEqual(loaded?.splits.count, detail.splits.count)
    }

    func testLoadDetailMissingID() throws {
        let loaded = try cache.loadWorkout(id: 99999)
        XCTAssertNil(loaded)
    }

    func testSaveDetailAlsoUpsertsWorkoutSummary() throws {
        let detail = DemoWorkoutLibrary.details[0]
        try cache.saveDetail(detail)
        let summaries = try cache.loadAllWorkouts()
        XCTAssertTrue(summaries.contains(where: { $0.id == detail.workout.id }))
    }

    func testSaveWorkoutsUpdatesExistingDetailSummary() throws {
        let detail = DemoWorkoutLibrary.details[0]
        try cache.saveDetail(detail)
        // Save an updated summary with a different date.
        var updatedWorkout = detail.workout
        updatedWorkout.date = Date(timeIntervalSince1970: 0)
        try cache.saveWorkouts([updatedWorkout])
        let loaded = try cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workout.date, updatedWorkout.date,
            "saveWorkouts should update the embedded workout in cached details")
    }

    // MARK: - deleteAll

    func testDeleteAllClearsWorkouts() throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        try cache.deleteAll()
        let loaded = try cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteAllClearsDetails() throws {
        let detail = DemoWorkoutLibrary.details[0]
        try cache.saveDetail(detail)
        try cache.deleteAll()
        let loaded = try cache.loadWorkout(id: detail.workout.id)
        XCTAssertNil(loaded)
    }

    func testDeleteAllOnEmptyCacheIsIdempotent() throws {
        try cache.deleteAll() // Should not throw
        let loaded = try cache.loadAllWorkouts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteAllThenSave() throws {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        try cache.saveWorkouts(workouts)
        try cache.deleteAll()
        try cache.saveWorkouts([workouts[0]])
        let loaded = try cache.loadAllWorkouts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, workouts[0].id)
    }

    // MARK: - Protocol conformance

    func testWorkoutCacheProtocolConformance() throws {
        let cache: WorkoutCache = InMemoryWorkoutCache()
        let detail = DemoWorkoutLibrary.details[0]
        try cache.saveDetail(detail)
        let loaded = try cache.loadWorkout(id: detail.workout.id)
        XCTAssertNotNil(loaded)
    }
}
