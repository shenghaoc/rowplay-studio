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
/// By default, creates a session with redirect protection that rejects
/// HTTPS-to-HTTP downgrade redirects to prevent token leakage. A custom
/// `URLSession` can be injected for testing or special configurations.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    /// Create a transport with built-in HTTPS redirect protection.
    public init() {
        let delegate = HTTPSRedirectDelegate()
        self.session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    /// Create a transport wrapping the given URL session.
    ///
    /// - Parameter session: The URL session to use.
    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// URLSession task delegate that rejects HTTP downgrade redirects.
///
/// Prevents the `Authorization` header from being sent over unencrypted
/// connections when a server responds with a redirect to `http://`.
private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if request.url?.scheme?.lowercased() == "https" {
            completionHandler(request)
        } else {
            // Block redirect to non-HTTPS URL.
            completionHandler(nil)
        }
    }
}
