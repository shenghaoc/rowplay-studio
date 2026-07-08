import Foundation

/// Loads workout data from the appropriate source following cache → demo → empty rules.
///
/// This is a pure domain type with no SwiftUI or AppKit dependencies,
/// making it testable with `InMemoryWorkoutCache` or throwing fakes.
public enum WorkoutLibraryLoader {
    /// Load workouts from the cache, falling back to demo data or empty as appropriate.
    ///
    /// - Parameters:
    ///   - cache: The workout cache to load from.
    ///   - demoModeEnabled: Whether demo mode is enabled; if true and the cache is
    ///     empty, demo workouts are returned.
    /// - Returns: A snapshot containing the loaded details and their source.
    /// - Throws: Propagates `WorkoutCacheError` cases (open, migration, query, decoding).
    ///   Cache failures never silently fall back to demo data.
    public static func load(
        cache: WorkoutCache,
        demoModeEnabled: Bool
    ) async throws -> WorkoutLibrarySnapshot {
        try cache.migrate()

        let workouts = try await cache.listWorkouts()

        if !workouts.isEmpty {
            let details = try await loadDetails(workouts: workouts, from: cache)
            return WorkoutLibrarySnapshot(details: details, source: .cache)
        }

        if demoModeEnabled {
            return WorkoutLibrarySnapshot(
                details: DemoWorkoutLibrary.details,
                source: .demo
            )
        }

        return WorkoutLibrarySnapshot(details: [], source: .empty)
    }

    /// Load full details for each workout summary from the cache.
    ///
    /// If `details(for:)` omits a workout that exists in `listWorkouts()`,
    /// a placeholder with empty strokes and splits is returned instead of failing.
    private static func loadDetails(
        workouts: [Workout],
        from cache: WorkoutCache
    ) async throws -> [WorkoutDetail] {
        let detailByID = try await cache.details(for: workouts.map(\.id))

        return workouts.map { workout in
            detailByID[workout.id] ?? WorkoutDetail(workout: workout, strokes: [], splits: [])
        }
    }
}
