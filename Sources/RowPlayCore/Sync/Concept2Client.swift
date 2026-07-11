import Foundation
import Synchronization

/// One page of results from the Concept2 logbook API.
///
/// Mirrors the pagination shape from the web app's `listWorkoutsPage`.
public struct Concept2Page: Equatable, Sendable {
    public var workouts: [Workout]
    public var totalPages: Int

    public init(workouts: [Workout], totalPages: Int) {
        self.workouts = workouts
        self.totalPages = totalPages
    }
}

/// Protocol for Concept2 logbook API access.
///
/// Implementations are `Sendable` so they can be used from any actor.
/// The real URLSession-based implementation is deferred to a follow-up PR;
/// this PR establishes the protocol boundary and a mock for tests.
public protocol Concept2APIClient: Sendable {
    /// Fetch one page of workout summaries from the logbook.
    ///
    /// - Parameters:
    ///   - page: 1-based page number.
    ///   - perPage: Results per page (Concept2 max is 250).
    /// - Returns: A page of workouts plus the total page count.
    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page

    /// Fetch full workout detail (including strokes and splits) by Concept2 workout ID.
    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail
}

/// Mock Concept2 API client returning deterministic fixture data.
///
/// Uses `DemoWorkoutLibrary` as the backing data source. Suitable for
/// tests, previews, and demo mode. Supports pagination simulation.
public final class MockConcept2Client: Concept2APIClient {
    private struct State: Sendable {
        var fetchWorkoutsCallCount = 0
        var fetchDetailRequestedIDs: [Int] = []
    }

    private let details: [WorkoutDetail]
    private let state = Mutex(State())

    /// Tracks the number of `fetchWorkouts` calls for test assertions.
    public var fetchWorkoutsCallCount: Int {
        state.withLock { $0.fetchWorkoutsCallCount }
    }

    /// Tracks the IDs requested via `fetchWorkoutDetail` for test assertions.
    public var fetchDetailRequestedIDs: [Int] {
        state.withLock { $0.fetchDetailRequestedIDs }
    }

    private let sorted: [WorkoutDetail]

    public init(details: [WorkoutDetail] = DemoWorkoutLibrary.details) {
        self.details = details
        self.sorted = details.sorted { $0.workout.date > $1.workout.date }
    }

    public func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        state.withLock {
            $0.fetchWorkoutsCallCount += 1
        }

        guard perPage > 0 else {
            return Concept2Page(workouts: [], totalPages: 1)
        }
        let workouts = sorted.map(\.workout)
        let totalPages = max(1, Int(ceil(Double(workouts.count) / Double(perPage))))
        let effectivePage = max(1, page)
        let start = (effectivePage - 1) * perPage
        let end = min(start + perPage, workouts.count)

        guard start < workouts.count else {
            return Concept2Page(workouts: [], totalPages: totalPages)
        }

        return Concept2Page(
            workouts: Array(workouts[start..<end]),
            totalPages: totalPages
        )
    }

    public func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        state.withLock {
            $0.fetchDetailRequestedIDs.append(id)
        }

        guard let detail = details.first(where: { $0.workout.id == id }) else {
            throw Concept2ClientError.workoutNotFound(id)
        }
        return detail
    }
}

/// Errors from Concept2 API client operations.
public enum Concept2ClientError: Error, Equatable, Sendable {
    /// The requested workout ID does not exist.
    case workoutNotFound(Int)
    /// The API returned an HTTP error.
    case httpError(statusCode: Int)
    /// The access token is missing or empty.
    case notAuthenticated
    /// The response could not be decoded.
    case decodingFailed
}
