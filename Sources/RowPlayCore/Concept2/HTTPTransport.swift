import Foundation

/// Abstraction over HTTP request execution.
///
/// Conformers accept a `URLRequest` and return the raw `Data` and `URLResponse`.
/// This protocol exists so tests can inject a fake transport without hitting
/// the network.
public protocol HTTPTransport: Sendable {
    /// Execute an HTTP request and return the response data and response object.
    ///
    /// - Parameter request: The URL request to execute.
    /// - Returns: A tuple of response data and the URL response.
    /// - Throws: Any transport-level error (network failure, timeout, etc.).
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// URLSession-backed transport for production use.
///
/// Wraps `URLSession.shared` by default. The session can be injected for
/// custom configuration (e.g., ephemeral sessions, delegate-based auth).
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    /// Create a transport wrapping the given URL session.
    ///
    /// - Parameter session: The URL session to use. Defaults to `.shared`.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
