import XCTest
@testable import RowPlayCore

/// A `WorkoutCache` that throws on every operation for error-propagation testing.
final class ThrowingWorkoutCache: WorkoutCache, @unchecked Sendable {
    func migrate() throws { throw TestCacheError.intentional }
    func save(detail: WorkoutDetail) async throws { throw TestCacheError.intentional }
    func save(details: [WorkoutDetail]) async throws { throw TestCacheError.intentional }
    func saveWorkouts(_ workouts: [Workout]) async throws { throw TestCacheError.intentional }
    func detail(id: Workout.ID) async throws -> WorkoutDetail? { throw TestCacheError.intentional }
    func listWorkouts() async throws -> [Workout] { throw TestCacheError.intentional }
    func delete(id: Workout.ID) async throws { throw TestCacheError.intentional }
    func deleteAll() async throws { throw TestCacheError.intentional }
}

/// Error type used by ``ThrowingWorkoutCache`` for assertion matching.
enum TestCacheError: Error {
    case intentional
}
