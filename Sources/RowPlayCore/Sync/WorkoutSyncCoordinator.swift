import Foundation

/// Orchestrates fetching workouts from the Concept2 logbook API and
/// persisting them into the local workout cache.
///
/// The coordinator depends only on protocols (`Concept2APIClient` and
/// `WorkoutCache`), not on concrete implementations. It does not own
/// tokens, does not use URLSession directly, and does not use SQLite
/// APIs directly.
///
/// Individual workout detail fetch or save failures are counted and
/// do not abort the sync. Fundamental failures (e.g., the summary
/// fetch itself fails) throw `WorkoutSyncError`.
public final class WorkoutSyncCoordinator: Sendable {
    private let client: Concept2APIClient
    private let cache: WorkoutCache
    private let logger: PrivacySafeLogger

    /// Number of workouts to request per API page.
    ///
    /// Matches the Concept2 API maximum and the web app's `listWorkoutsPage`.
    private let perPage: Int

    /// Create a sync coordinator.
    ///
    /// - Parameters:
    ///   - client: The Concept2 API client to fetch workouts from.
    ///   - cache: The workout cache to persist details into.
    ///   - perPage: Results per API page. Defaults to 250 (the API max).
    ///   - logger: Privacy-safe logger for diagnostics.
    public init(
        client: Concept2APIClient,
        cache: WorkoutCache,
        perPage: Int = 250,
        logger: PrivacySafeLogger = PrivacySafeLogger(category: "sync-coordinator")
    ) {
        precondition(perPage > 0, "perPage must be greater than 0")
        self.client = client
        self.cache = cache
        self.perPage = perPage
        self.logger = logger
    }

    /// Fetch all workouts from the Concept2 logbook and save details
    /// into the local cache.
    ///
    /// Pages through workout summaries, then fetches and saves detail
    /// for each workout. Individual failures are counted but do not
    /// abort the sync.
    ///
    /// - Returns: A ``WorkoutSyncResult`` with counts and timestamps.
    /// - Throws: ``WorkoutSyncError`` if the summary fetch fails fundamentally.
    public func syncAll() async throws -> WorkoutSyncResult {
        let startedAt = Date()

        // 0. Ensure the cache schema is ready before doing any work.
        try cache.migrate()

        // 1. Fetch all workout summaries across pages.
        let workouts: [Workout]
        do {
            workouts = try await fetchAllSummaries()
        } catch {
            let message = redact(error)
            logger.error("Summary fetch failed: \(message)")
            throw WorkoutSyncError.clientFailed(message)
        }

        let fetchedCount = workouts.count

        // 2. Fetch detail for each workout and save to cache.
        var savedCount = 0
        var failedCount = 0

        for workout in workouts {
            do {
                let detail = try await client.fetchWorkoutDetail(id: workout.id)
                do {
                    try await cache.save(detail: detail)
                    savedCount += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let message = redact(error)
                    logger.warn("Cache save failed for workout \(workout.id): \(message)")
                    failedCount += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = redact(error)
                logger.warn("Detail fetch failed for workout \(workout.id): \(message)")
                failedCount += 1
                // Abort early on authentication or rate-limit failures to avoid
                // spamming the API with invalid requests for every remaining workout.
                if shouldAbortSync(error) {
                    throw WorkoutSyncError.clientFailed(message)
                }
            }
        }

        let finishedAt = Date()

        return WorkoutSyncResult(
            fetchedCount: fetchedCount,
            savedCount: savedCount,
            failedCount: failedCount,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    // MARK: - Private

    /// Fetch all workout summaries by paging through the API.
    private func fetchAllSummaries() async throws -> [Workout] {
        var allWorkouts: [Workout] = []
        var page = 1
        var totalPages = 1

        repeat {
            let result = try await client.fetchWorkouts(page: page, perPage: perPage)
            allWorkouts.append(contentsOf: result.workouts)
            totalPages = result.totalPages
            page += 1
        } while page <= totalPages

        return allWorkouts
    }

    /// Check whether an error indicates an authentication/authorization failure
    /// or rate-limiting that should abort the sync loop.
    private func shouldAbortSync(_ error: Error) -> Bool {
        if let clientError = error as? Concept2ClientError {
            switch clientError {
            case .notAuthenticated:
                return true
            case let .httpError(statusCode):
                return statusCode == 401 || statusCode == 403 || statusCode == 429
            default:
                return false
            }
        }
        if let concept2Error = error as? Concept2Error {
            return concept2Error == .unauthorized
                || concept2Error == .forbidden
                || concept2Error == .rateLimited
        }
        return false
    }
}
