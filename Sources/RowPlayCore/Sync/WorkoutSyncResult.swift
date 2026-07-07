import Foundation

/// Result of a completed sync operation.
///
/// Reports how many workouts were fetched, saved, and failed during
/// the sync. Timestamps allow callers to track sync duration.
public struct WorkoutSyncResult: Equatable, Sendable {
    /// Number of workout summaries fetched from the Concept2 API.
    public var fetchedCount: Int
    /// Number of workout details successfully saved to the cache.
    public var savedCount: Int
    /// Number of workout details that failed to fetch or save.
    public var failedCount: Int
    /// When the sync started.
    public var startedAt: Date
    /// When the sync finished.
    public var finishedAt: Date

    public init(
        fetchedCount: Int,
        savedCount: Int,
        failedCount: Int,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.fetchedCount = fetchedCount
        self.savedCount = savedCount
        self.failedCount = failedCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
