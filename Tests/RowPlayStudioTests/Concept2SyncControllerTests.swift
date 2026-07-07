import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class Concept2SyncControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RowPlayStudioTests.Concept2Sync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveTokenStoresTrimmedTokenAndMarksConnected() throws {
        let tokenStore = FakeTokenStore()
        let controller = Concept2SyncController(tokenStore: tokenStore)

        controller.saveToken("  test-token  ")

        XCTAssertEqual(try tokenStore.loadToken(), "test-token")
        XCTAssertTrue(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Concept2 token saved.")
    }

    func testSyncNowLoadsCacheIntoLibraryAndDisablesDemoMode() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let detail = makeDetail(id: 12_345)
        let cache = InMemoryWorkoutCache()
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { cache },
            clientFactory: { _ in MockConcept2Client(details: [detail]) }
        )
        let library = WorkoutLibrary.demo(defaults: defaults)

        await controller.syncNow(into: library)

        XCTAssertEqual(library.details, [detail])
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.demoModeEnabledKey))
        XCTAssertEqual(controller.syncState.totalWorkouts, 1)
        XCTAssertEqual(controller.statusMessage, "Synced 1 workouts.")
    }

    func testSyncNowWithoutTokenDoesNotCreateClient() async {
        var clientWasCreated = false
        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(),
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in
                clientWasCreated = true
                return MockConcept2Client(details: [])
            }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.syncNow(into: library)

        XCTAssertFalse(clientWasCreated)
        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Add a Concept2 token before syncing.")
    }

    func testDisconnectDeletesTokenCacheAndClearsLibrary() async throws {
        let detail = makeDetail(id: 7)
        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: detail)
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { cache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [detail], defaults: defaults)

        await controller.disconnect(library: library)

        let cachedWorkouts = try await cache.listWorkouts()
        XCTAssertNil(try tokenStore.loadToken())
        XCTAssertTrue(cachedWorkouts.isEmpty)
        XCTAssertTrue(library.isEmpty)
        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Concept2 disconnected.")
    }

    private func makeDetail(id: Int) -> WorkoutDetail {
        WorkoutDetail(
            workout: Workout(
                id: id,
                date: Date(timeIntervalSince1970: TimeInterval(id)),
                sport: .rower,
                distance: 2_000,
                time: 480,
                pace: 120,
                workoutType: "JustRow",
                hasStrokeData: false
            ),
            strokes: [],
            splits: []
        )
    }
}
