import Foundation

/// Errors from the sync coordinator.
///
/// Descriptions are privacy-safe: they never include BYOT tokens,
/// Authorization headers, or full raw workout payloads. Sufficient
/// context for debugging (e.g., workout ID) is preserved.
public enum WorkoutSyncError: Error, Equatable, Sendable {
    /// The Concept2 API client failed (e.g., network error, auth failure).
    case clientFailed(String)
    /// The workout cache failed (e.g., migration error, save failure).
    case cacheFailed(String)
    /// Mapping from API response to domain model failed.
    case mappingFailed(String)
}

extension WorkoutSyncError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .clientFailed(detail):
            "Sync client failed: \(redact(detail))"
        case let .cacheFailed(detail):
            "Sync cache failed: \(redact(detail))"
        case let .mappingFailed(detail):
            "Sync mapping failed: \(redact(detail))"
        }
    }
}
