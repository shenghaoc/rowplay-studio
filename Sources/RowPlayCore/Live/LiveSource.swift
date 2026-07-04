import Foundation

/// Result of a live poll, mirroring the web's LivePollResult.
public struct LivePollResult: Equatable, Sendable {
    public let workouts: [Workout]
    public let added: Int
    public let total: Int

    public init(workouts: [Workout], added: Int, total: Int) {
        self.workouts = workouts
        self.added = added
        self.total = total
    }
}

/// Injectable protocol for live workout data sources.
///
/// Mock and future Concept2 polling implementations share this interface.
/// The `knownIDs` parameter allows the source to filter out workouts the
/// caller already knows about.
public protocol LiveSource: Sendable {
    func poll(knownIDs: Set<Int>) async throws -> LivePollResult
}
