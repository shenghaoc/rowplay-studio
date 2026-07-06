import Foundation

/// Errors from URLSession Concept2 client operations.
///
/// Error descriptions are privacy-safe: they never include the BYOT token,
/// Authorization header values, raw response payloads, or other sensitive data.
public enum Concept2Error: Error, Equatable {
    /// The server returned HTTP 401 Unauthorized.
    case unauthorized
    /// The server returned HTTP 403 Forbidden.
    case forbidden
    /// The server returned HTTP 429 Too Many Requests.
    case rateLimited
    /// The server returned a non-2xx status code not covered by a specific case.
    case httpError(statusCode: Int)
    /// URL construction failed.
    case invalidURL(String)
    /// The response body could not be decoded.
    case decodingFailed
}

extension Concept2Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unauthorized:
            "Concept2 API request unauthorized (401)"
        case .forbidden:
            "Concept2 API request forbidden (403)"
        case .rateLimited:
            "Concept2 API rate limited (429)"
        case let .httpError(statusCode):
            "Concept2 API HTTP error (\(statusCode))"
        case let .invalidURL(path):
            "Concept2 API invalid URL for path: \(path)"
        case .decodingFailed:
            "Concept2 API response decoding failed"
        }
    }
}

/// Transport-level errors from the underlying HTTP layer.
///
/// These are thrown when the transport itself fails (network timeout,
/// DNS resolution, etc.), not when the server returns an error status.
/// The underlying error is preserved for diagnostics but its description
/// is not included in `Concept2Error` to avoid leaking sensitive data.
public struct Concept2TransportError: Error, Sendable {
    /// The underlying error from the transport layer.
    public let underlying: any Error

    public init(underlying: any Error) {
        self.underlying = underlying
    }
}

extension Concept2TransportError: CustomStringConvertible {
    public var description: String {
        // Do not include underlying.localizedDescription — it may contain
        // URL or header details that include the token.
        "Concept2 API transport error"
    }
}
