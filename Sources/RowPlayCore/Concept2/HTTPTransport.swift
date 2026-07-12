import Foundation
import Synchronization
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
/// HTTPS-to-HTTP downgrade redirects and cross-host HTTPS redirects to
/// prevent token leakage. A custom `URLSessionConfiguration` can be injected
/// for testing or special configurations while keeping that protection
/// installed.
public final class URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession
    private let redirectDelegate: HTTPSRedirectDelegate

    /// Create a transport with built-in HTTPS redirect protection.
    ///
    /// - Parameter configuration: The URL session configuration to use.
    public init(configuration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        // Security: Enforce strict timeouts to prevent resource exhaustion (DoS)
        // from slow or unresponsive remote servers.
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0
        return config
    }()) {
        let delegate = HTTPSRedirectDelegate()
        self.redirectDelegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    @available(*, unavailable, message: "Use init(configuration:) so HTTPS downgrade redirect protection is installed.")
    public init(session: URLSession) {
        fatalError("Unavailable")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { [session, redirectDelegate] continuation in
            let taskReference = Mutex(Optional<URLSessionDataTask>.none)
            let task = session.dataTask(with: request) { data, response, error in
                let taskID = taskReference.withLock { $0?.taskIdentifier }
                if let taskID,
                   redirectDelegate.consumeBlockedRedirect(for: taskID) {
                    continuation.resume(throwing: Concept2Error.insecureRedirectBlocked)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            taskReference.withLock { $0 = task }
            task.resume()
        }
    }
}

/// URLSession task delegate that rejects insecure redirects.
///
/// Allows redirects only when the new request is HTTPS and targets the same
/// host as the original request (host comparison is case-insensitive per
/// RFC 3986). Blocks HTTP downgrades and cross-host HTTPS redirects so the
/// `Authorization` header is never sent to an unencrypted or unintended host.
/// Tracks blocked redirects so the transport can throw a typed error.
final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    /// Task identifiers for which a redirect was blocked.
    private let blockedTaskIDs = Mutex(Set<Int>())

    /// Returns `true` and clears the flag if the given task had its redirect blocked.
    func consumeBlockedRedirect(for taskID: Int) -> Bool {
        blockedTaskIDs.withLock {
            $0.remove(taskID) != nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let isHTTPS = request.url?.scheme?.lowercased() == "https"
        // Hostnames are case-insensitive (RFC 3986). Require non-nil hosts so
        // nil == nil does not incorrectly treat malformed URLs as same-host.
        let newHost = request.url?.host?.lowercased()
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let isSameHost = newHost != nil && newHost == originalHost

        if isHTTPS && isSameHost {
            completionHandler(request)
        } else {
            // Block redirect to non-HTTPS URL or different host to prevent token leakage.
            _ = blockedTaskIDs.withLock { $0.insert(task.taskIdentifier) }
            completionHandler(nil)
        }
    }
}
