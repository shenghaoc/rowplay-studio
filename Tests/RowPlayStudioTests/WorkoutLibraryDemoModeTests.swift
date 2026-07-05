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
        let library = WorkoutLibrary.demo(defaults: defaults)
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
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        XCTAssertFalse(library.isEmpty)
    }

    func testDemoLibraryStartsEmptyWhenDemoModeDisabled() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        XCTAssertTrue(library.isEmpty)
    }

    func testDemoModeNotificationReloadsDemoDataWhenEnabled() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)

        XCTAssertFalse(library.isEmpty)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
    }

    func testDemoModeNotificationClearsDemoDataWhenDisabled() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)

        XCTAssertTrue(library.isEmpty)
    }

    func testDemoModeNotificationPreservesNonDemoWorkoutsWhenDisabled() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let realWorkout = WorkoutDetail(
            workout: Workout(
                id: 99_999,
                date: Date(),
                sport: .rower,
                distance: 2_000,
                time: 480,
                pace: 120,
                workoutType: "Imported",
                source: "Local",
                hasStrokeData: false
            ),
            strokes: [],
            splits: []
        )
        let library = WorkoutLibrary(
            details: DemoWorkoutLibrary.details + [realWorkout],
            defaults: defaults
        )

        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)

        XCTAssertEqual(library.details, [realWorkout])
    }

    func testUnrelatedDefaultsChangeDoesNotReloadDemoData() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: [], defaults: defaults)

        defaults.set("imperial", forKey: AppPreferences.preferredDistanceUnitKey)

        XCTAssertTrue(library.isEmpty)
    }
}
