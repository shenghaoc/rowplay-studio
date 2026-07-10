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

/// A WorkoutCache that throws from migrate but still allows deleteAll.
private final class MigrateFailingDeleteTrackingCache: WorkoutCache, @unchecked Sendable {
    private struct MigrationError: Error, CustomStringConvertible {
        var description: String { "Migration failed" }
    }

    private let wrapped: InMemoryWorkoutCache
    private let lock = NSLock()
    private var _deleteAllCallCount = 0

    init(wrapping cache: InMemoryWorkoutCache) {
        self.wrapped = cache
    }

    var deleteAllCallCount: Int {
        lock.withLock { _deleteAllCallCount }
    }

    func migrate() throws {
        throw MigrationError()
    }

    func save(detail: WorkoutDetail) async throws { try await wrapped.save(detail: detail) }
    func save(details: [WorkoutDetail]) async throws { try await wrapped.save(details: details) }
    func saveWorkouts(_ workouts: [Workout]) async throws { try await wrapped.saveWorkouts(workouts) }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { try await wrapped.detail(id: id) }
    func listWorkouts() async throws -> [Workout] { try await wrapped.listWorkouts() }
    func delete(id: Workout.ID) async throws { try await wrapped.delete(id: id) }
    func deleteAll() async throws {
        lock.withLock { _deleteAllCallCount += 1 }
        try await wrapped.deleteAll()
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

    func testLoadCachedWorkoutsLoadsDemoFallbackWithoutToken() async {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(),
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.loadCachedWorkouts(into: library)

        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(library.librarySource, .demo)
        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
        XCTAssertNil(controller.statusMessage)
    }

    func testLoadCachedWorkoutsHonorsDisabledDemoModeWithoutToken() async {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(),
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.loadCachedWorkouts(into: library)

        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(library.librarySource, .empty)
        XCTAssertTrue(library.details.isEmpty)
        XCTAssertNil(controller.statusMessage)
    }

    func testLoadCachedWorkoutsUsesCacheWhenDemoModeIsOn() async throws {
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

        await controller.loadCachedWorkouts(into: library)

        XCTAssertEqual(library.details, [detail], "Cache data must take priority over demo data")
        XCTAssertEqual(controller.syncState.totalWorkouts, 1)
    }

    func testLoadCachedWorkoutsDoesNotReportDemoFallbackAsCached() async {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(storedToken: "test-token"),
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.loadCachedWorkouts(into: library)

        XCTAssertEqual(library.librarySource, .demo)
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

    func testDisconnectAttemptsCacheDeleteWhenMigrationFails() async throws {
        let detail = makeDetail(id: 111)
        let wrappedCache = InMemoryWorkoutCache()
        try await wrappedCache.save(detail: detail)
        let failingCache = MigrateFailingDeleteTrackingCache(wrapping: wrappedCache)
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { failingCache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [detail], defaults: defaults)

        await controller.disconnect(library: library)

        let cachedWorkouts = try await wrappedCache.listWorkouts()
        XCTAssertNil(try tokenStore.loadToken())
        XCTAssertEqual(failingCache.deleteAllCallCount, 1)
        XCTAssertTrue(cachedWorkouts.isEmpty)
        XCTAssertTrue(library.isEmpty)
        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.syncState.totalWorkouts, 0)
        XCTAssertNotNil(controller.syncState.lastError)
        XCTAssertEqual(controller.statusMessage, "Concept2 token deleted; local data cleanup failed.")
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

    // MARK: - Annotation Cleanup on Disconnect

    func testDisconnectPurgesAnnotations() async throws {
        let annotationStore = InMemoryAnnotationStore()
        _ = try await annotationStore.saveAnnotation(
            workoutId: 1,
            Annotation(id: 0, timestamp: 30, text: "Test annotation", createdAt: 100)
        )

        let cache = InMemoryWorkoutCache()
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { cache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(
            details: [],
            annotationStore: annotationStore,
            defaults: defaults
        )

        await controller.disconnect(library: library)

        let annotations = try await annotationStore.loadAnnotations(workoutId: 1)
        XCTAssertTrue(annotations.isEmpty, "Disconnect must purge all annotations")
        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Concept2 disconnected.")
    }

    func testDisconnectReportsCleanupFailureWhenAnnotationDeletionThrows() async throws {
        let annotationStore = FailingDeleteAnnotationStore()
        let cache = InMemoryWorkoutCache()
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { cache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(
            details: [],
            annotationStore: annotationStore,
            defaults: defaults
        )

        await controller.disconnect(library: library)

        XCTAssertTrue(controller.isConnected == false)
        XCTAssertTrue(controller.statusMessage?.contains("cleanup failed") ?? false,
                       "Expected cleanup failure message, got: \(controller.statusMessage ?? "nil")")
    }

    func testDisconnectReportsCleanupFailureWhenCacheAndAnnotationBothFail() async throws {
        let secretToken = "abcdef0123456789abcdef0123456789"
        let annotationStore = FailingDeleteAnnotationStore()

        let cache = InMemoryWorkoutCache()
        try await cache.save(detail: makeDetail(id: 1))
        let failingCache = FailingDeleteCache(wrapping: cache, token: secretToken)

        let tokenStore = FakeTokenStore(storedToken: secretToken)
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { failingCache },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(
            details: [makeDetail(id: 1)],
            annotationStore: annotationStore,
            defaults: defaults
        )

        await controller.disconnect(library: library)

        XCTAssertFalse(controller.syncState.lastError?.contains(secretToken) ?? false,
                        "syncState.lastError must not contain the raw token")
        XCTAssertTrue(controller.statusMessage?.contains("cleanup failed") ?? false,
                       "Expected cleanup failure message, got: \(controller.statusMessage ?? "nil")")
    }

    // MARK: - Silent Failure Fixes

    func testInitStoresErrorWhenTokenLoadFails() {
        struct TokenLoadError: Error {}
        let tokenStore = FakeTokenStore()
        tokenStore.loadError = TokenLoadError()

        let controller = Concept2SyncController(tokenStore: tokenStore)

        XCTAssertFalse(controller.isConnected)
        XCTAssertNotNil(controller.syncState.lastError)
        XCTAssertEqual(controller.statusMessage, "Concept2 connection unavailable.")
    }

    func testSaveTokenStoresErrorOnFailure() {
        struct TokenSaveError: Error {}
        let tokenStore = FakeTokenStore()
        tokenStore.saveError = TokenSaveError()

        let controller = Concept2SyncController(tokenStore: tokenStore)
        controller.saveToken("test-token")

        XCTAssertNotNil(controller.syncState.lastError)
        XCTAssertEqual(controller.statusMessage, "Could not save Concept2 token.")
    }

    func testDisconnectStoresErrorWhenTokenDeleteFails() async {
        struct TokenDeleteError: Error {}
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        tokenStore.deleteError = TokenDeleteError()

        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { InMemoryWorkoutCache() },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.disconnect(library: library)

        XCTAssertNotNil(controller.syncState.lastError)
        XCTAssertEqual(controller.statusMessage, "Could not delete Concept2 token.")
    }

    func testLoadCachedWorkoutsStoresErrorWhenCacheFactoryThrows() async {
        struct CacheOpenError: Error {}
        let tokenStore = FakeTokenStore(storedToken: "test-token")
        let controller = Concept2SyncController(
            tokenStore: tokenStore,
            cacheFactory: { throw CacheOpenError() },
            clientFactory: { _ in MockConcept2Client(details: []) }
        )
        let library = WorkoutLibrary(details: [], defaults: defaults)

        await controller.loadCachedWorkouts(into: library)

        XCTAssertNotNil(controller.syncState.lastError)
        XCTAssertEqual(controller.statusMessage, "Could not load cached Concept2 workouts.")
    }

    func testLoadCachedWorkoutsReportsCacheWhenReplacingDemoWithFewerRows() async throws {
        // Library starts with demo data (17 items), cache has fewer.
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
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
        let demoCount = library.details.count
        XCTAssertGreaterThan(demoCount, 1, "Demo library should have multiple workouts")

        await controller.loadCachedWorkouts(into: library)

        // Cache has 1 workout, demo had 17. loadedCount (1) < previousCount (17).
        XCTAssertEqual(library.details.count, 1)
        XCTAssertEqual(controller.statusMessage, "Loaded 1 cached workouts.")
    }

    func testSyncNowLeavesDemoModeEnabledWhenPostSyncCacheReloadFails() async throws {
        defaults.set(true, forKey: AppPreferences.demoModeEnabledKey)
        let detail = makeDetail(id: 12_345)
        let cache = ListFailingWorkoutCache()
        let controller = Concept2SyncController(
            tokenStore: FakeTokenStore(storedToken: "test-token"),
            cacheFactory: { cache },
            clientFactory: { _ in MockConcept2Client(details: [detail]) }
        )
        let library = WorkoutLibrary.demo(defaults: defaults)

        await controller.syncNow(into: library)

        XCTAssertEqual(library.details.count, DemoWorkoutLibrary.details.count)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.demoModeEnabledKey))
        XCTAssertEqual(controller.statusMessage, "Concept2 sync failed.")
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

private final class ListFailingWorkoutCache: WorkoutCache, @unchecked Sendable {
    private enum ListError: Error { case intentional }

    private let wrapped = InMemoryWorkoutCache()

    func migrate() throws {}
    func save(detail: WorkoutDetail) async throws { try await wrapped.save(detail: detail) }
    func save(details: [WorkoutDetail]) async throws { try await wrapped.save(details: details) }
    func saveWorkouts(_ workouts: [Workout]) async throws { try await wrapped.saveWorkouts(workouts) }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { try await wrapped.detail(id: id) }
    func details(for ids: [Workout.ID]) async throws -> [Workout.ID: WorkoutDetail] {
        try await wrapped.details(for: ids)
    }
    func listWorkouts() async throws -> [Workout] { throw ListError.intentional }
    func delete(id: Workout.ID) async throws { try await wrapped.delete(id: id) }
    func deleteAll() async throws { try await wrapped.deleteAll() }
}

/// An AnnotationStore that throws from deleteAll to test cleanup failure reporting.
private final class FailingDeleteAnnotationStore: AnnotationStore, @unchecked Sendable {
    private let wrapped = InMemoryAnnotationStore()

    func loadAnnotations(workoutId: Int) async throws -> [Annotation] {
        try await wrapped.loadAnnotations(workoutId: workoutId)
    }

    func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation {
        try await wrapped.saveAnnotation(workoutId: workoutId, annotation)
    }

    func deleteAnnotation(workoutId: Int, id: Int) async throws {
        try await wrapped.deleteAnnotation(workoutId: workoutId, id: id)
    }

    func deleteAll() async throws {
        struct IntentionalError: Error {}
        throw IntentionalError()
    }
}
