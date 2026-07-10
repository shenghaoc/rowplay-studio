import XCTest
@testable import RowPlayCore

/// Opt-in authenticated Concept2 smoke tests.
///
/// These tests validate real API request/response integration against the
/// Concept2 logbook API. They are skipped unless `ROWPLAY_CONCEPT2_TOKEN`
/// is set in the environment. CI passes without the token — tests are
/// skipped, not failed.
///
/// Run locally:
/// ```
/// ROWPLAY_CONCEPT2_TOKEN="<paste token locally>" swift test --filter Concept2AuthenticatedSmokeTests
/// ```
///
/// Privacy: the token is never printed, logged, committed, or included in
/// error descriptions.
final class Concept2AuthenticatedSmokeTests: XCTestCase {
    // MARK: - Environment

    private static var hasToken: Bool {
        guard let token = ProcessInfo.processInfo.environment["ROWPLAY_CONCEPT2_TOKEN"],
              !token.isEmpty else {
            return false
        }
        return true
    }

    private static var token: String? {
        ProcessInfo.processInfo.environment["ROWPLAY_CONCEPT2_TOKEN"]
    }

    private static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ROWPLAY_CONCEPT2_BASE_URL"],
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        return URLSessionConcept2Client.defaultBaseURL
    }

    private func requireToken() throws -> String {
        guard Self.hasToken, let token = Self.token else {
            throw XCTSkip("Set ROWPLAY_CONCEPT2_TOKEN to run authenticated Concept2 smoke tests.")
        }
        return token
    }

    // MARK: - 1. Fetch Workout Summaries

    func testAuthenticatedFetchWorkoutSummariesSmoke() async throws {
        let token = try requireToken()
        let client = URLSessionConcept2Client(
            baseURL: Self.baseURL,
            token: token
        )

        let page = try await client.fetchWorkouts(page: 1, perPage: 5)

        XCTAssertGreaterThanOrEqual(page.totalPages, 1,
            "totalPages should be >= 1")

        // Verify workouts decode to valid domain types.
        for workout in page.workouts {
            XCTAssertGreaterThan(workout.id, 0,
                "Workout ID should be positive")
            XCTAssertGreaterThanOrEqual(workout.distance, 0,
                "Workout distance should not be negative")
        }
    }

    // MARK: - 2. Fetch Workout Detail

    func testAuthenticatedFetchWorkoutDetailSmoke() async throws {
        let token = try requireToken()
        let client = URLSessionConcept2Client(
            baseURL: Self.baseURL,
            token: token
        )

        // Fetch a small page to get a workout ID.
        let page = try await client.fetchWorkouts(page: 1, perPage: 5)

        guard let firstWorkout = page.workouts.first else {
            throw XCTSkip("No workouts available to fetch detail for.")
        }

        let detail = try await client.fetchWorkoutDetail(id: firstWorkout.id)

        // Verify the detail maps to valid domain types.
        XCTAssertEqual(detail.workout.id, firstWorkout.id,
            "Detail workout ID should match the requested ID")
    }

    // MARK: - 3. Error Redaction

    func testAuthenticatedSmokeErrorRedactsToken() async throws {
        // This test runs without network access — it verifies that error
        // descriptions from the Concept2 client never leak the token.
        let fakeToken = "test-secret-token-abc123"
        let transport = FakeHTTPTransport()
        transport.result = .failure(URLError(.notConnectedToInternet))

        let client = URLSessionConcept2Client(
            baseURL: URL(string: "https://log.concept2.com")!,
            token: fakeToken,
            transport: transport
        )

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 5)
            XCTFail("Expected error from failed transport")
        } catch {
            let desc = String(describing: error)

            XCTAssertFalse(desc.contains(fakeToken),
                "Error description must not contain the token. Got: \(desc)")
            XCTAssertFalse(desc.contains("Authorization"),
                "Error description must not contain 'Authorization'. Got: \(desc)")
            XCTAssertFalse(desc.contains("Bearer"),
                "Error description must not contain 'Bearer'. Got: \(desc)")
        }
    }
}
