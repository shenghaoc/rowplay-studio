import Foundation

/// URLSession-backed implementation of ``Concept2APIClient``.
///
/// Injects the BYOT token into every request via the `Authorization` header.
/// The token is held in memory only — never logged, persisted, or included
/// in error descriptions.
///
/// The transport is injectable via ``HTTPTransport`` for testability.
/// Production code uses ``URLSessionHTTPTransport``; tests use a fake.
public final class URLSessionConcept2Client: Concept2APIClient, @unchecked Sendable {
    private let baseURL: URL
    private let token: String
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let logger: PrivacySafeLogger

    /// The Concept2 logbook API base URL.
    public static let defaultBaseURL = URL(string: "https://logbook.concept2.com")!

    /// Create a client with an injected BYOT token.
    ///
    /// - Parameters:
    ///   - baseURL: The Concept2 API base URL. Defaults to the production logbook URL.
    ///   - token: The BYOT access token. Held in memory only.
    ///   - transport: The HTTP transport to use. Defaults to `URLSessionHTTPTransport`.
    ///   - decoder: JSON decoder for response parsing.
    ///   - logger: Privacy-safe logger for diagnostics. Defaults to `"concept2-client"` category.
    public init(
        baseURL: URL = defaultBaseURL,
        token: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        decoder: JSONDecoder = JSONDecoder(),
        logger: PrivacySafeLogger = PrivacySafeLogger(category: "concept2-client")
    ) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
        self.decoder = decoder
        self.logger = logger
    }

    // MARK: - Concept2APIClient

    public func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page {
        let response: Concept2WorkoutSummaryResponse = try await request(
            endpoint: .workoutSummaries(page: page, number: perPage)
        )
        let workouts = response.data.map(Concept2Mapper.mapWorkout)
        let totalPages = response.meta?.pagination?.totalPages ?? 1
        return Concept2Page(workouts: workouts, totalPages: totalPages)
    }

    public func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail {
        let response: Concept2WorkoutDetailResponse = try await request(
            endpoint: .workoutDetail(id: id)
        )
        let raw = response.data
        let workout = Concept2Mapper.mapWorkout(raw)

        // Map splits from the raw response.
        // Note: The web app calls a separate /strokes endpoint for per-stroke data.
        // For this foundation, we map from the detail response only.
        // Full stroke fetching will be added when sync orchestration is implemented.
        let splits = Concept2Mapper.mapSplits(raw)

        return WorkoutDetail(
            workout: workout,
            strokes: [],
            splits: splits
        )
    }

    // MARK: - Private

    /// Build a request for the given endpoint with auth and accept headers.
    private func buildRequest(endpoint: Concept2Endpoint) throws -> URLRequest {
        let url = try endpoint.url(from: baseURL)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.c2logbook.v1+json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Execute a request and decode the response.
    private func request<T: Decodable>(endpoint: Concept2Endpoint) async throws -> T {
        let urlRequest = try buildRequest(endpoint: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch {
            throw Concept2TransportError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Concept2Error.httpError(statusCode: 0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapHTTPError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.warn("Concept2 response decoding failed: \(error)")
            throw Concept2Error.decodingFailed
        }
    }

    /// Map an HTTP status code to a typed error.
    private func mapHTTPError(statusCode: Int) -> Concept2Error {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .rateLimited
        default:  return .httpError(statusCode: statusCode)
        }
    }
}
