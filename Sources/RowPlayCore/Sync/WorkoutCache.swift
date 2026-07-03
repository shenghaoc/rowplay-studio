import Foundation

/// Protocol for local workout storage.
///
/// The cache stores workout summaries and detail records for offline-first
/// access. Implementations do not prescribe a specific storage backend —
/// a future SQLite implementation can conform without changing callers.
///
/// `deleteAll()` is the disconnect/logout path: it clears the entire cache.
public protocol WorkoutCache: Sendable {
    /// Persist workout summaries, upserting by workout ID.
    func saveWorkouts(_ workouts: [Workout]) throws
    /// Persist a full workout detail (including strokes and splits).
    func saveDetail(_ detail: WorkoutDetail) throws
    /// Load all cached workout summaries, newest first.
    func loadAllWorkouts() throws -> [Workout]
    /// Load full detail for a specific workout, or nil if not cached.
    func loadWorkout(id: Int) throws -> WorkoutDetail?
    /// Delete all cached data (disconnect/logout).
    func deleteAll() throws
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

    public func saveWorkouts(_ workouts: [Workout]) throws {
        lock.lock()
        defer { lock.unlock() }
        for workout in workouts {
            self.workouts[workout.id] = workout
        }
    }

    public func saveDetail(_ detail: WorkoutDetail) throws {
        lock.lock()
        defer { lock.unlock() }
        details[detail.workout.id] = detail
        // Also upsert the summary.
        workouts[detail.workout.id] = detail.workout
    }

    public func loadAllWorkouts() throws -> [Workout] {
        lock.lock()
        defer { lock.unlock() }
        return workouts.values.sorted { $0.date > $1.date }
    }

    public func loadWorkout(id: Int) throws -> WorkoutDetail? {
        lock.lock()
        defer { lock.unlock() }
        return details[id]
    }

    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        workouts.removeAll()
        details.removeAll()
    }
}
