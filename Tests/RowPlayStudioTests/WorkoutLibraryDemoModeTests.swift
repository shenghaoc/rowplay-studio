import XCTest
@testable import RowPlayCore
@testable import RowPlayMacOS
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
        XCTAssertEqual(library.librarySource, .demo)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
        XCTAssertEqual(library.details.first?.id, DemoWorkoutLibrary.defaultWorkoutID)
    }

    func testDemoLibraryLoadsWhenDemoModeEnabled() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        XCTAssertFalse(library.isEmpty)
        XCTAssertEqual(library.librarySource, .demo)
    }

    func testDemoLibraryStartsEmptyWhenDemoModeDisabled() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        XCTAssertTrue(library.isEmpty)
        XCTAssertEqual(library.librarySource, .empty)
    }

    func testDemoModeNotificationReloadsDemoDataWhenEnabled() async {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        XCTAssertFalse(library.isEmpty)
        XCTAssertEqual(library.librarySource, .demo)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
    }

    func testDemoModeNotificationDoesNotAppendDemoDataWhenExistingWorkoutsPresent() async {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let realWorkout = makeRealWorkoutDetail()
        let library = WorkoutLibrary(details: [realWorkout], defaults: defaults)

        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        XCTAssertEqual(library.details, [realWorkout])
        XCTAssertEqual(library.librarySource, .cache)
    }

    func testDemoModeNotificationClearsDemoDataWhenDisabled() async {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary.demo(defaults: defaults)

        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        XCTAssertTrue(library.isEmpty)
        XCTAssertEqual(library.librarySource, .empty)
    }

    func testDemoModeNotificationPreservesNonDemoWorkoutsWhenDisabled() async {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let realWorkout = makeRealWorkoutDetail()
        let library = WorkoutLibrary(
            details: DemoWorkoutLibrary.details + [realWorkout],
            defaults: defaults
        )

        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        XCTAssertEqual(library.details, [realWorkout])
    }

    func testDemoModeNotificationPreservesRealWorkoutWithDemoIDWhenDisabled() async {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let realWorkout = makeRealWorkoutDetail(id: DemoWorkoutLibrary.defaultWorkoutID)
        let library = WorkoutLibrary(details: [realWorkout], defaults: defaults)

        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        await waitForDemoModeNotification()

        XCTAssertEqual(library.details, [realWorkout])
    }

    func testUnrelatedDefaultsChangeDoesNotReloadDemoData() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: [], defaults: defaults)

        defaults.set("imperial", forKey: AppPreferences.preferredDistanceUnitKey)

        XCTAssertTrue(library.isEmpty)
    }

    private func makeRealWorkoutDetail(id: Int = 99_999) -> WorkoutDetail {
        WorkoutDetail(
            workout: Workout(
                id: id,
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
    }

    private func waitForDemoModeNotification() async {
        // Allow the NotificationCenter → Task { @MainActor } dispatch to settle.
        // A single Task.yield() is sufficient in most environments; the loop
        // provides resilience against CI/slow-machine scheduling variance.
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
