import Foundation

/// An immutable snapshot of workout data produced by ``WorkoutLibraryLoader``.
///
/// The ``source`` should be semantically consistent with ``details``:
/// `.cache` implies data from the persistent store, `.demo` implies
/// deterministic fixture data, and `.empty` implies no data.
public struct WorkoutLibrarySnapshot: Sendable, Equatable {
    /// The workout details loaded from the data source.
    public let details: [WorkoutDetail]
    /// Which data source provided the workouts.
    public let source: WorkoutLibrarySource

    init(details: [WorkoutDetail], source: WorkoutLibrarySource) {
        self.details = details
        self.source = source
    }
}
