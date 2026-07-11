import XCTest
@testable import RowPlayCore
@testable import RowPlayPlatform

@MainActor
final class WorkoutLibrarySourceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RowPlayStudioTests.Source.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - loadFromSource

    func testLoadFromSourceSetsLibrarySourceToCache() async throws {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let detail = makeDetail(id: 42)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: detail)
        let library = WorkoutLibrary(details: [], defaults: defaults)

        try await library.loadFromSource(cache: cache)

        XCTAssertEqual(library.librarySource, .cache)
        XCTAssertEqual(library.details, [detail])
        XCTAssertTrue(library.demoDetailIDs.isEmpty)
    }

    func testLoadFromSourceSetsLibrarySourceToDemo() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let cache = InMemoryWorkoutCache()
        let library = WorkoutLibrary(details: [], defaults: defaults)

        try await library.loadFromSource(cache: cache)

        XCTAssertEqual(library.librarySource, .demo)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
        XCTAssertFalse(library.demoDetailIDs.isEmpty)
    }

    func testLoadFromSourceSetsLibrarySourceToEmpty() async throws {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let cache = InMemoryWorkoutCache()
        let library = WorkoutLibrary(details: [], defaults: defaults)

        try await library.loadFromSource(cache: cache)

        XCTAssertEqual(library.librarySource, .empty)
        XCTAssertTrue(library.details.isEmpty)
        XCTAssertTrue(library.demoDetailIDs.isEmpty)
    }

    func testLoadFromSourceReplacesExistingData() async throws {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let oldDetail = makeDetail(id: 1)
        let newDetail = makeDetail(id: 2)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: newDetail)
        let library = WorkoutLibrary(details: [oldDetail], defaults: defaults)
        XCTAssertEqual(library.details.count, 1)

        try await library.loadFromSource(cache: cache)

        XCTAssertEqual(library.details, [newDetail])
        XCTAssertFalse(library.details.contains(oldDetail))
    }

    func testLoadFromSourceResetsQueryOnlyWhenSourceChanges() async throws {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: makeDetail(id: 1))
        let library = WorkoutLibrary(details: [], defaults: defaults)

        // First load: source changes from .empty to .cache → query resets.
        try await library.loadFromSource(cache: cache)
        XCTAssertEqual(library.librarySource, .cache)
        library.query.searchText = "custom filter"

        // Second load: source stays .cache → query preserved.
        try await library.loadFromSource(cache: cache)
        XCTAssertEqual(library.librarySource, .cache)
        XCTAssertEqual(library.query.searchText, "custom filter",
            "Query should be preserved when source does not change")
    }

    func testLoadFromSourceResetsQueryWhenSourceChanges() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let cache = InMemoryWorkoutCache()
        let library = WorkoutLibrary(details: [], defaults: defaults)

        // First load: source is .demo.
        try await library.loadFromSource(cache: cache)
        XCTAssertEqual(library.librarySource, .demo)
        library.query.searchText = "custom filter"

        // Add cache data; source changes from .demo to .cache → query resets.
        try await cache.save(detail: makeDetail(id: 99))
        try await library.loadFromSource(cache: cache)
        XCTAssertEqual(library.librarySource, .cache)
        XCTAssertNil(library.query.searchText, "Query should reset when source changes")
    }

    func testLoadFromSourceThrowsOnCacheError() async {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: [], defaults: defaults)
        let throwingCache = ThrowingListCache()

        do {
            try await library.loadFromSource(cache: throwingCache)
            XCTFail("Expected error to be thrown")
        } catch {
            // Error propagated — library unchanged.
        }

        XCTAssertTrue(library.details.isEmpty)
        XCTAssertEqual(library.librarySource, .empty)
    }

    // MARK: - disableDemoModeIfNeeded

    func testDisableDemoModeIfNeededDisablesWhenEnabled() {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: [], defaults: defaults)

        library.disableDemoModeIfNeeded()

        XCTAssertFalse(defaults.bool(forKey: AppPreferences.demoModeEnabledKey))
    }

    func testDisableDemoModeIfNeededNoopWhenAlreadyDisabled() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let library = WorkoutLibrary(details: [], defaults: defaults)

        library.disableDemoModeIfNeeded()

        XCTAssertFalse(defaults.bool(forKey: AppPreferences.demoModeEnabledKey))
    }

    // MARK: - clearData resets librarySource

    func testClearDataResetsLibrarySource() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: makeDetail(id: 1))
        let library = WorkoutLibrary(details: [], defaults: defaults)

        try await library.loadFromSource(cache: cache)
        XCTAssertEqual(library.librarySource, .cache)

        library.clearData()

        XCTAssertEqual(library.librarySource, .empty)
        XCTAssertTrue(library.details.isEmpty)
    }

    func testComparisonCandidatesCacheInvalidatesWhenDetailsChange() {
        let target = makeDetail(id: 1)
        let firstCandidate = makeDetail(id: 2)
        let library = WorkoutLibrary(details: [target, firstCandidate], defaults: defaults)

        XCTAssertEqual(library.comparisonCandidates(for: target.id).map(\.id), [firstCandidate.id])

        let newerCandidate = makeDetail(id: 3)
        library.details.append(newerCandidate)

        XCTAssertEqual(
            library.comparisonCandidates(for: target.id).map(\.id),
            [newerCandidate.id, firstCandidate.id]
        )
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

private enum ListCacheError: Error { case intentional }

/// A WorkoutCache that throws on listWorkouts to test error propagation through loadFromSource.
private final class ThrowingListCache: WorkoutCache {
    func migrate() throws {}
    func save(detail: WorkoutDetail) async throws {}
    func save(details: [WorkoutDetail]) async throws {}
    func saveWorkouts(_ workouts: [Workout]) async throws {}
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { nil }
    func listWorkouts() async throws -> [Workout] { throw ListCacheError.intentional }
    func delete(id: Workout.ID) async throws {}
    func deleteAll() async throws {}
}
