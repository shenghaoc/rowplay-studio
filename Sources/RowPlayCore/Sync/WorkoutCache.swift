import Foundation

/// Protocol for local workout storage.
///
/// The cache stores workout summaries and detail records for offline-first
/// access. Implementations do not prescribe a specific storage backend —
/// async calls allow a future SQLite implementation to avoid blocking callers.
///
/// `deleteAll()` is the disconnect/logout path: it clears the entire cache.
public protocol WorkoutCache: Sendable {
    /// Persist workout summaries, upserting by workout ID.
    func saveWorkouts(_ workouts: [Workout]) async throws
    /// Persist a full workout detail (including strokes and splits).
    func saveDetail(_ detail: WorkoutDetail) async throws
    /// Load all cached workout summaries, newest first.
    func loadAllWorkouts() async throws -> [Workout]
    /// Load full detail for a specific workout, or nil if not cached.
    func loadWorkout(id: Int) async throws -> WorkoutDetail?
    /// Delete all cached data (disconnect/logout).
    func deleteAll() async throws
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

    public func saveWorkouts(_ workouts: [Workout]) async throws {
        lock.withLock {
            for workout in workouts {
                self.workouts[workout.id] = workout
                // Keep cached detail in sync: update the summary embedded in any
                // existing detail so loadWorkout(id:) doesn't return stale metadata.
                if var detail = details[workout.id] {
                    detail.workout = workout
                    details[workout.id] = detail
                }
            }
        }
    }

    public func saveDetail(_ detail: WorkoutDetail) async throws {
        lock.withLock {
            details[detail.workout.id] = detail
            // Also upsert the summary.
            workouts[detail.workout.id] = detail.workout
        }
    }

    public func loadAllWorkouts() async throws -> [Workout] {
        lock.withLock {
            workouts.values.sorted { $0.date > $1.date }
        }
    }

    public func loadWorkout(id: Int) async throws -> WorkoutDetail? {
        lock.withLock {
            details[id]
        }
    }

    public func deleteAll() async throws {
        lock.withLock {
            workouts.removeAll()
            details.removeAll()
        }
    }
}
