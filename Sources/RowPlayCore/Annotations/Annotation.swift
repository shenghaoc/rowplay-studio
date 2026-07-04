import Foundation

/// A coach/self timestamped note attached to a workout.
public struct Annotation: Codable, Equatable, Identifiable, Sendable {
    /// Opaque id (auto-increment in persistent store; local counter in memory).
    public var id: Int
    /// Seconds since workout start — snaps to the nearest stroke.
    public var timestamp: TimeInterval
    /// Free-text coaching note.
    public var text: String
    /// Epoch milliseconds when the annotation was created.
    public var createdAt: Int64

    public init(id: Int, timestamp: TimeInterval, text: String, createdAt: Int64) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.createdAt = createdAt
    }

    /// Validate annotation fields. Returns nil if valid, error message otherwise.
    public func validate() -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Annotation text is required."
        }
        if text.count > 1000 {
            return "Annotation text must be 1000 characters or fewer."
        }
        if !timestamp.isFinite || timestamp < 0 {
            return "Invalid timestamp."
        }
        return nil
    }
}
