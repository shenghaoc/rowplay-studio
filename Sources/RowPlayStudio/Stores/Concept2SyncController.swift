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
            statusMessage = "Concept2 connection unavailable."
        }
    }

    var canSync: Bool {
        isConnected && !syncState.inProgress
    }

    func loadCachedWorkouts(into library: WorkoutLibrary) async {
        guard isConnected else { return }

        do {
            let cache = try resolvedCache()
            try cache.migrate()
            let details = try await loadDetails(from: cache)
            let tracker = resolvedTracker(cache: cache)
            await tracker.refreshWorkoutCount()
            syncState = tracker.state

            guard !details.isEmpty else { return }
            library.replaceWithSyncedDetails(details)
            statusMessage = "Loaded \(details.count) cached workouts."
        } catch {
            if let tracker {
                await tracker.syncFailed(error: error)
                syncState = tracker.state
            } else {
                syncState.lastError = redact(error)
                syncState.lastErrorDate = Date()
            }
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
            let details = try await loadDetails(from: cache)

            library.replaceWithSyncedDetails(details)
            await tracker.syncCompleted()
            syncState = tracker.state
            statusMessage = syncSummary(for: result)
            isConnected = true
        } catch is CancellationError {
            syncState.inProgress = false
            statusMessage = "Concept2 sync cancelled."
        } catch {
            if let tracker {
                await tracker.syncFailed(error: error)
                syncState = tracker.state
            } else {
                syncState.inProgress = false
                syncState.lastError = redact(error)
                syncState.lastErrorDate = Date()
            }
            statusMessage = "Concept2 sync failed."
        }
    }

    func disconnect(library: WorkoutLibrary) async {
        do {
            try tokenStore.deleteToken()
            isConnected = false
        } catch {
            statusMessage = "Could not delete Concept2 token."
            return
        }

        var cacheCleanupFailed = false
        do {
            let cache = try resolvedCache()
            // Migrate so a fresh SQLite cache instance can open the DB.
            try cache.migrate()
        } catch {
            cacheCleanupFailed = true
            syncState.lastError = redact(error)
            syncState.lastErrorDate = Date()
        }

        if !cacheCleanupFailed, let cache = try? resolvedCache() {
            do {
                try await cache.deleteAll()
                let tracker = resolvedTracker(cache: cache)
                await tracker.refreshWorkoutCount()
                syncState = tracker.state
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

    private func resolvedTracker(cache: any WorkoutCache) -> SyncStateTracker {
        if let tracker {
            return tracker
        }
        let tracker = SyncStateTracker(cache: cache)
        self.tracker = tracker
        return tracker
    }

    private func loadDetails(from cache: any WorkoutCache) async throws -> [WorkoutDetail] {
        let workouts = try await cache.listWorkouts()
        var details: [WorkoutDetail] = []
        details.reserveCapacity(workouts.count)

        for workout in workouts {
            if let detail = try await cache.detail(id: workout.id) {
                details.append(detail)
            } else {
                details.append(WorkoutDetail(workout: workout, strokes: [], splits: []))
            }
        }

        return details
    }

    private func syncSummary(for result: WorkoutSyncResult) -> String {
        if result.failedCount == 0 {
            return "Synced \(result.savedCount) workouts."
        }
        return "Synced \(result.savedCount) workouts; \(result.failedCount) failed."
    }
}
