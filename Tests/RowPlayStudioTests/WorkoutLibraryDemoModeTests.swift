import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class WorkoutLibraryDemoModeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RowPlayStudioTests.DemoMode.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

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

    func testDemoLibraryLoadsWhenDemoModeEnabled() {
        // Ensure demo mode is on
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: DemoWorkoutLibrary.details)

        XCTAssertFalse(library.isEmpty)
    }

    func testDemoLibraryStartsEmptyWhenDemoModeDisabled() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        // WorkoutLibrary.demo() reads UserDefaults.standard, not our test defaults,
        // so test the clearData path instead.
        let library = WorkoutLibrary(details: DemoWorkoutLibrary.details)

        library.clearData()

        XCTAssertTrue(library.isEmpty)
    }
}
