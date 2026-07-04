import Foundation

/// Tracks the state of a Concept2 sync operation.
///
/// Mirrors the web app's `SyncState` from `data.ts`, translated into
/// native local concepts (no D1/KV assumptions).
public struct SyncState: Equatable, Sendable {
    /// When the last successful sync completed.
    public var lastSyncDate: Date?
    /// Total number of workouts in the local cache.
    public var totalWorkouts: Int
    /// Whether a sync is currently in progress.
    public var inProgress: Bool
    /// Error message from the last failed sync, if any.
    public var lastError: String?
    /// When the last sync error occurred.
    public var lastErrorDate: Date?

    public init(
        lastSyncDate: Date? = nil,
        totalWorkouts: Int = 0,
        inProgress: Bool = false,
        lastError: String? = nil,
        lastErrorDate: Date? = nil
    ) {
        self.lastSyncDate = lastSyncDate
        self.totalWorkouts = totalWorkouts
        self.inProgress = inProgress
        self.lastError = lastError
        self.lastErrorDate = lastErrorDate
    }
}

/// Observable tracker for sync state transitions.
///
/// Reads workout count from the cache protocol. Transitions:
/// - idle → syncing (on sync start)
/// - syncing → complete (on sync success)
/// - syncing → error (on sync failure)
/// - error → syncing (on retry)
@available(macOS 14.0, *)
@Observable
@MainActor
public final class SyncStateTracker {
    public private(set) var state: SyncState

    private let cache: WorkoutCache
    private let logger: PrivacySafeLogger

    public init(cache: WorkoutCache, logger: PrivacySafeLogger = PrivacySafeLogger(category: "sync")) {
        self.cache = cache
        self.logger = logger
        self.state = SyncState()
        refreshWorkoutCount()
    }

    /// Refresh the workout count from the cache.
    public func refreshWorkoutCount() {
        do {
            let workouts = try cache.loadAllWorkouts()
            state.totalWorkouts = workouts.count
        } catch {
            logger.warn("Failed to count cached workouts: \(error)")
        }
    }

    /// Mark a sync as in progress. Clears any previous error.
    public func syncStarted() {
        state.inProgress = true
        state.lastError = nil
        state.lastErrorDate = nil
    }

    /// Mark a sync as successfully completed.
    public func syncCompleted() {
        state.inProgress = false
        state.lastSyncDate = Date()
        state.lastError = nil
        state.lastErrorDate = nil
        refreshWorkoutCount()
    }

    /// Record a sync failure.
    public func syncFailed(error: Error) {
        state.inProgress = false
        state.lastError = redact(error)
        state.lastErrorDate = Date()
        logger.error("Sync failed: \(error)")
    }
}
