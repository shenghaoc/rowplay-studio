import Foundation

/// Lightweight state for a sync coordinator operation.
///
/// Tracks whether a sync is idle, in progress, or has completed.
/// This is a pure value type — it does not drive UI or observe cache
/// state. Use `SyncStateTracker` for the full observable sync state.
public enum WorkoutSyncState: Equatable, Sendable {
    /// No sync has been requested or the last sync finished.
    case idle
    /// A sync is currently running.
    case syncing
    /// A sync completed successfully.
    case completed(WorkoutSyncResult)
    /// A sync failed with a fundamental error.
    case failed(WorkoutSyncError)
}
