import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

/// A Concept2APIClient that delegates fetchWorkouts to a caller-provided handler and throws on fetchWorkoutDetail.
private final class FailingConcept2Client: Concept2APIClient, Sendable {
    private let fetchWorkoutsHandler: @Sendable (Int, Int) async throws -> Concept2Page

    init(fetchWorkoutsHandler: @escaping @Sendable (Int, Int) async throws -> Concept2Page) {
        self.fetchWorkoutsHandler = fetchWorkoutsHandler
    }

    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        try await fetchWorkoutsHandler(page, perPage)
    }

    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        throw Concept2ClientError.workoutNotFound(id)
    }
}

/// A WorkoutCache that wraps another cache but throws from deleteAll with a leaky error message.
private final class FailingDeleteCache: WorkoutCache, @unchecked Sendable {
    private let wrapped: InMemoryWorkoutCache
    private let token: String

    init(wrapping cache: InMemoryWorkoutCache, token: String) {
        self.wrapped = cache
        self.token = token
    }

    func migrate() throws { try wrapped.migrate() }
    func save(detail: WorkoutDetail) async throws { try await wrapped.save(detail: detail) }
    func save(details: [WorkoutDetail]) async throws { try await wrapped.save(details: details) }
    func saveWorkouts(_ workouts: [Workout]) async throws { try await wrapped.saveWorkouts(workouts) }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { try await wrapped.detail(id: id) }
    func listWorkouts() async throws -> [Workout] { try await wrapped.listWorkouts() }
    func delete(id: Workout.ID) async throws { try await wrapped.delete(id: id) }
    func deleteAll() async throws {
        struct LeakyError: Error, CustomStringConvertible {
            let token: String
            var description: String { "Cache cleanup failed with token=\(token)" }
        }
        throw LeakyError(token: token)
    }
}

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

    func testLoadCachedWorkoutsHydratesLibraryAfterRelaunch() async throws {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let detail = makeDetail(id: 42)
        let cachePath = temporarySQLitePath()
        defer { try? FileManager.default.removeItem(atPath: cachePath) }

        let seedCache = try SQLiteWorkoutCache(path: cachePath)
        try seedCache.migrate()
        try await seedCache.save(detail: detail)

        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(storedToken: "test-token"),
            cacheFactory: { try SQLiteWorkoutCache(path: cachePath) },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary.demo(defaults: defaults)
        XCTAssertTrue(library.isEmpty)

        await controller.loadCachedWorkouts(into: library)

        XCTAssertEqual(library.details, [detail])
        XCTAssertEqual(controller.syncState.totalWorkouts, 1)
        XCTAssertEqual(controller.statusMessage, "Loaded 1 cached workouts.")
    }

    func testLoadCachedWorkoutsPreservesDemoDataWhenDemoModeIsOn() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let detail = makeDetail(id: 77)
        let cachePath = temporarySQLitePath()
        defer { try? FileManager.default.removeItem(atPath: cachePath) }

        let seedCache = try SQLiteWorkoutCache(path: cachePath)
        try seedCache.migrate()
        try await seedCache.save(detail: detail)

        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(storedToken: "test-token"),
            cacheFactory: { try SQLiteWorkoutCache(path: cachePath) },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary.demo(defaults: defaults)
        XCTAssertFalse(library.isEmpty, "Demo mode populates library with demo data")
        let demoDetails = library.details

        await controller.loadCachedWorkouts(into: library)

        XCTAssertEqual(library.details, demoDetails, "Launch cache hydration must not replace active demo data")
        XCTAssertEqual(controller.syncState.totalWorkouts, 0)
        XCTAssertNil(controller.statusMessage)
    }

    func testDisconnectAfterRelaunchMigratesAndDeletesSQLiteCache() async throws {
        let detail = makeDetail(id: 99)
        let cachePath = temporarySQLitePath()
        defer { try? FileManager.default.removeItem(atPath: cachePath) }

        let seedCache = try SQLiteWorkoutCache(path: cachePath)
        try seedCache.migrate()
        try await seedCache.save(detail: detail)

        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { try SQLiteWorkoutCache(path: cachePath) },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [detail], defaults: defaults)

        await controller.disconnect(library: library)

        let verifyCache = try SQLiteWorkoutCache(path: cachePath)
        try verifyCache.migrate()
        let cachedWorkouts = try await verifyCache.listWorkouts()

        XCTAssertNil(try tokenStore.loadToken())
        XCTAssertTrue(cachedWorkouts.isEmpty)
        XCTAssertTrue(library.isEmpty)
        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.syncState.totalWorkouts, 0)
        XCTAssertEqual(controller.statusMessage, "Concept2 disconnected.")
    }

    func testSummaryFetchErrorDoesNotExposeToken() async throws {
        let secretToken = "abcdef0123456789abcdef0123456789"
        let tokenStore = FakeTokenStore(storedToken: secretToken)

        // Use a custom error whose description embeds the token,
        // so we can verify that redact() strips it before it reaches
        // the user-facing error state. This mirrors the pattern in
        // WorkoutSyncCoordinatorTests.testErrorsDoNotExposeToken.
        struct LeakyClientError: Error, CustomStringConvertible {
            let token: String
            var description: String { "Auth failed with token=\(token)" }
        }

        let failingClient = FailingConcept2Client { _, _ in
            throw LeakyClientError(token: secretToken)
        }

        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in failingClient }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.syncNow(into: library)

        // statusMessage is always the hardcoded "Concept2 sync failed." on error —
        // it never contains error details. The meaningful assertion is lastError,
        // which stores redact(error) and must not leak the token.
        XCTAssertFalse(controller.syncState.lastError?.contains(secretToken) ?? false,
                        "syncState.lastError must not contain the raw token")
    }

    func testDisconnectErrorDoesNotExposeToken() async throws {
        let secretToken = "abcdef0123456789abcdef0123456789"
        let tokenStore = FakeTokenStore(storedToken: secretToken)

        let cache = InMemoryWorkoutCache()
        // Pre-populate cache so deleteAll is called, then make it throw.
        try await cache.save(detail: makeDetail(id: 1))

        // InMemoryWorkoutCache.deleteAll() doesn't throw, so we use a wrapper
        // whose deleteAll throws an error embedding the token.
        let failingCache = FailingDeleteCache(wrapping: cache, token: secretToken)

        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { failingCache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [makeDetail(id: 1)], defaults: defaults)

        await controller.disconnect(library: library)

        XCTAssertFalse(controller.syncState.lastError?.contains(secretToken) ?? false,
                        "syncState.lastError must not contain the raw token on disconnect")
    }

    private func temporarySQLitePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RowPlayStudioTests-\(UUID().uuidString).sqlite")
            .path
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
