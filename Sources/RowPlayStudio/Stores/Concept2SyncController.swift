import Foundation
import RowPlayCore

@MainActor
final class Concept2SyncController: ObservableObject {
    typealias CacheFactory = () throws -> any WorkoutCache
    typealias ClientFactory = (String) -> any Concept2APIClient

    @Published private(set) var syncState: SyncState
    @Published private(set) var isConnected: Bool
    @Published private(set) var statusMessage: String?

    private let tokenStore: any TokenStore
    private let cacheFactory: CacheFactory
    private let clientFactory: ClientFactory
    private var cache: (any WorkoutCache)?
    private var tracker: SyncStateTracker?

    init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        cacheFactory: @escaping CacheFactory = {
            try SQLiteWorkoutCache(path: try Concept2SyncController.defaultCachePath())
        },
        clientFactory: @escaping ClientFactory = { token in
            URLSessionConcept2Client(token: token)
        }
    ) {
        self.tokenStore = tokenStore
        self.cacheFactory = cacheFactory
        self.clientFactory = clientFactory
        self.syncState = SyncState()

        do {
            isConnected = try tokenStore.loadToken()?.isEmpty == false
        } catch {
            isConnected = false
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
            statusMessage = "Concept2 connection unavailable."
        }
    }

    var canSync: Bool {
        isConnected && !syncState.inProgress
    }

    func loadCachedWorkouts(into library: WorkoutLibrary) async {
        guard isConnected, !syncState.inProgress else { return }

        do {
            let cache = try resolvedCache()
            let previousCount = library.details.count
            try await library.loadFromSource(cache: cache)

            let tracker = resolvedTracker(cache: cache)
            await tracker.refreshWorkoutCount()
            syncState = tracker.state

            let loadedCount = library.details.count
            if loadedCount > previousCount {
                statusMessage = "Loaded \(loadedCount) cached workouts."
            }
        } catch {
            await handleSyncError(error)
            statusMessage = "Could not load cached Concept2 workouts."
        }
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a Concept2 token."
            return
        }
        guard trimmed.count <= 4_096 else {
            statusMessage = "Concept2 token is too long."
            return
        }

        do {
            try tokenStore.saveToken(trimmed)
            isConnected = true
            statusMessage = "Concept2 token saved."
        } catch {
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
            statusMessage = "Could not save Concept2 token."
        }
    }

    func syncNow(into library: WorkoutLibrary) async {
        guard !syncState.inProgress else { return }

        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                isConnected = false
                statusMessage = "Add a Concept2 token before syncing."
                return
            }

            let cache = try resolvedCache()
            let tracker = resolvedTracker(cache: cache)
            tracker.syncStarted()
            syncState = tracker.state
            statusMessage = nil

            let coordinator = WorkoutSyncCoordinator(
                client: clientFactory(token),
                cache: cache
            )
            let result = try await coordinator.syncAll()

            // Syncing real Concept2 data replaces demo mode.
            library.disableDemoModeIfNeeded()
            try await library.loadFromSource(cache: cache)
            await tracker.syncCompleted()
            syncState = tracker.state
            statusMessage = syncSummary(for: result)
            isConnected = true
        } catch is CancellationError {
            syncState.inProgress = false
            statusMessage = "Concept2 sync cancelled."
        } catch {
            await handleSyncError(error, resetInProgress: true)
            statusMessage = "Concept2 sync failed."
        }
    }

    func disconnect(library: WorkoutLibrary) async {
        do {
            try tokenStore.deleteToken()
            isConnected = false
        } catch {
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
            statusMessage = "Could not delete Concept2 token."
            return
        }

        var cacheCleanupFailed = false
        var cacheForCleanup: (any WorkoutCache)?
        do {
            let cache = try resolvedCache()
            cacheForCleanup = cache
            // Migrate so a fresh SQLite cache instance can open the DB.
            try cache.migrate()
        } catch {
            cacheCleanupFailed = true
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
        }

        if let cache = cacheForCleanup {
            do {
                try await cache.deleteAll()
                if cacheCleanupFailed {
                    syncState.totalWorkouts = 0
                    syncState.inProgress = false
                } else {
                    let tracker = resolvedTracker(cache: cache)
                    await tracker.refreshWorkoutCount()
                    syncState = tracker.state
                }
            } catch {
                cacheCleanupFailed = true
                syncState.lastError = redact(error)
                syncState.lastErrorDate = Date()
            }
        }

        library.clearData()
        statusMessage = cacheCleanupFailed
            ? "Concept2 token deleted; cache cleanup failed."
            : "Concept2 disconnected."
    }

    nonisolated static func defaultCachePath(fileManager: FileManager = .default) throws -> String {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("RowPlayStudio", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("workouts.sqlite").path
    }

    private func resolvedCache() throws -> any WorkoutCache {
        if let cache {
            return cache
        }
        let cache = try cacheFactory()
        self.cache = cache
        return cache
    }

    private func handleSyncError(_ error: Error, resetInProgress: Bool = false) async {
        if let tracker {
            await tracker.syncFailed(error: error)
            syncState = tracker.state
        } else {
            if resetInProgress {
                syncState.inProgress = false
            }
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
        }
    }

    private func resolvedTracker(cache: any WorkoutCache) -> SyncStateTracker {
        if let tracker {
            return tracker
        }
        let tracker = SyncStateTracker(cache: cache)
        self.tracker = tracker
        return tracker
    }

    private func syncSummary(for result: WorkoutSyncResult) -> String {
        if result.failedCount == 0 {
            return "Synced \(result.savedCount) workouts."
        }
        return "Synced \(result.savedCount) workouts; \(result.failedCount) failed."
    }
}
