import Foundation

/// An immutable snapshot of workout data produced by ``WorkoutLibraryLoader``.
public struct WorkoutLibrarySnapshot: Sendable, Equatable {
    /// The workout details loaded from the data source.
    public let details: [WorkoutDetail]
    /// Which data source provided the workouts.
    public let source: WorkoutLibrarySource

    public init(details: [WorkoutDetail], source: WorkoutLibrarySource) {
        self.details = details
        self.source = source
    }
}
