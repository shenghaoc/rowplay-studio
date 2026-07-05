import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class WorkoutLibraryDemoModeTests: XCTestCase {
    func testClearDataRemovesDemoWorkoutsAndResetsQuery() {
        let library = WorkoutLibrary.demo()
        library.query.searchText = "row"

        library.clearData()

        XCTAssertTrue(library.isEmpty)
        XCTAssertTrue(library.details.isEmpty)
        XCTAssertTrue(library.workouts.isEmpty)
        XCTAssertTrue(library.filteredWorkouts.isEmpty)
        XCTAssertNil(library.query.searchText)
    }

    func testReloadDemoDataRestoresDemoWorkouts() {
        let library = WorkoutLibrary(details: [])

        library.reloadDemoData()

        XCTAssertFalse(library.isEmpty)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
        XCTAssertEqual(library.details.first?.id, DemoWorkoutLibrary.defaultWorkoutID)
    }
}
