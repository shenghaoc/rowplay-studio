import Foundation

/// Indicates which data source the workout library loaded from.
public enum WorkoutLibrarySource: String, Sendable, Equatable {
    /// Workouts loaded from the persistent cache (SQLite).
    case cache
    /// Workouts loaded from deterministic demo fixtures.
    case demo
    /// No workouts available; cache is empty and demo mode is disabled.
    case empty
}
