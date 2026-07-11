import Foundation

/// Concept2 logbook API endpoints.
///
/// Each case represents a single API endpoint and can construct the full URL
/// from a base URL. The paths and query parameters match the web app's
/// `Concept2Client` in `src/lib/server/concept2.ts`.
public enum Concept2Endpoint: Sendable {
    /// List workout summaries with pagination.
    case workoutSummaries(page: Int, number: Int)
    /// Fetch full workout detail by Concept2 workout ID.
    case workoutDetail(id: Int)
    /// Fetch per-stroke data for a workout.
    case workoutStrokes(id: Int)

    /// The API path component (without the base URL).
    public var path: String {
        switch self {
        case .workoutSummaries:
            "/api/users/me/results"
        case let .workoutDetail(id):
            "/api/users/me/results/\(id)"
        case let .workoutStrokes(id):
            "/api/users/me/results/\(id)/strokes"
        }
    }

    /// Query items to append to the URL.
    public var queryItems: [URLQueryItem] {
        switch self {
        case let .workoutSummaries(page, number):
            [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "number", value: String(number)),
            ]
        case .workoutDetail:
            [URLQueryItem(name: "include", value: "metadata")]
        case .workoutStrokes:
            []
        }
    }

    /// Build the full URL from a base URL.
    ///
    /// - Parameter baseURL: The Concept2 API base URL (e.g., `https://logbook.concept2.com`).
    /// - Returns: The complete URL with path and query parameters.
    /// - Throws: `Concept2Error.invalidURL` if URL construction fails.
    public func url(from baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw Concept2Error.invalidURL(path)
        }
        let basePath = baseURL.path
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = basePath.hasSuffix("/") ? basePath + cleanPath : basePath + "/" + cleanPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw Concept2Error.invalidURL(path)
        }
        return url
    }
}
