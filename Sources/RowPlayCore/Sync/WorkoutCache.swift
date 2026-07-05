import Foundation

/// Protocol for local workout storage.
///
/// The cache stores workout summaries and detail records for offline-first
/// access. Implementations do not prescribe a specific storage backend —
/// async calls allow a future SQLite implementation to avoid blocking callers.
///
/// `deleteAll()` is the disconnect/logout path: it clears the entire cache.
public protocol WorkoutCache: Sendable {
    /// Ensure the backing store is ready for use.
    func migrate() throws
    /// Persist a full workout detail (including strokes and splits).
    func save(detail: WorkoutDetail) async throws
    /// Persist full workout details, upserting by workout ID.
    func save(details: [WorkoutDetail]) async throws
    /// Persist workout summaries, upserting by workout ID.
    func saveWorkouts(_ workouts: [Workout]) async throws
    /// Load full detail for a specific workout, or nil if not cached.
    func detail(id: Workout.ID) async throws -> WorkoutDetail?
    /// Load all cached workout summaries, newest first.
    func listWorkouts() async throws -> [Workout]
    /// Delete a single workout by ID. No-op if the ID does not exist.
    func delete(id: Workout.ID) async throws
    /// Delete all cached data (disconnect/logout).
    func deleteAll() async throws
}

public extension WorkoutCache {
    /// Legacy Phase 4 name for `save(detail:)`.
    func saveDetail(_ detail: WorkoutDetail) async throws {
        try await save(detail: detail)
    }

    /// Legacy Phase 4 name for `listWorkouts()`.
    func loadAllWorkouts() async throws -> [Workout] {
        try await listWorkouts()
    }

    /// Legacy Phase 4 name for `detail(id:)`.
    func loadWorkout(id: Workout.ID) async throws -> WorkoutDetail? {
        try await detail(id: id)
    }
}

/// In-memory workout cache for tests, previews, and early integration.
///
/// Stores workouts and details in dictionaries keyed by workout ID.
/// Thread-safe via NSLock.
public final class InMemoryWorkoutCache: WorkoutCache, @unchecked Sendable {
    private var workouts: [Int: Workout] = [:]
    private var details: [Int: WorkoutDetail] = [:]
    private let lock = NSLock()

    public init() {}

    public func migrate() throws {}

    public func save(detail: WorkoutDetail) async throws {
        lock.withLock {
            details[detail.workout.id] = detail
            // Also upsert the summary.
            workouts[detail.workout.id] = detail.workout
        }
    }

    public func save(details: [WorkoutDetail]) async throws {
        lock.withLock {
            for detail in details {
                self.details[detail.workout.id] = detail
                workouts[detail.workout.id] = detail.workout
            }
        }
    }

    public func saveWorkouts(_ workouts: [Workout]) async throws {
        lock.withLock {
            for workout in workouts {
                self.workouts[workout.id] = workout
                // Keep cached detail in sync: update the summary embedded in any
                // existing detail so detail(id:) doesn't return stale metadata.
                if var detail = details[workout.id] {
                    detail.workout = workout
                    details[workout.id] = detail
                }
            }
        }
    }

    public func listWorkouts() async throws -> [Workout] {
        lock.withLock {
            workouts.values.sorted { $0.date > $1.date }
        }
    }

    public func detail(id: Workout.ID) async throws -> WorkoutDetail? {
        lock.withLock {
            details[id]
        }
    }

    public func delete(id: Int) async throws {
        lock.withLock {
            workouts.removeValue(forKey: id)
            details.removeValue(forKey: id)
        }
    }

    public func deleteAll() async throws {
        lock.withLock {
            workouts.removeAll()
            details.removeAll()
        }
    }
}
