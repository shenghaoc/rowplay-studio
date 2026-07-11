import Foundation

/// Errors from SQLite workout cache operations.
///
/// Each case carries a diagnostic message for debugging. Messages must not
/// include full workout payloads to avoid leaking user data into logs.
public enum WorkoutCacheError: Error, Equatable, Sendable {
    /// The SQLite database could not be opened.
    case openFailed(String)
    /// Schema migration failed.
    case migrationFailed(String)
    /// A SQL query (INSERT, SELECT, DELETE, BEGIN, COMMIT) failed.
    case queryFailed(String)
    /// JSON encoding of a WorkoutDetail failed.
    case encodingFailed(String)
    /// JSON decoding of a stored WorkoutDetail failed.
    case decodingFailed(String)
}
