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
public final class URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession
    private let redirectDelegate: HTTPSRedirectDelegate?

    /// Create a transport with built-in HTTPS redirect protection.
    public init() {
        let delegate = HTTPSRedirectDelegate()
        self.redirectDelegate = delegate
        self.session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    /// Create a transport wrapping the given URL session.
    ///
    /// No redirect protection is applied to custom sessions.
    /// - Parameter session: The URL session to use.
    public init(session: URLSession) {
        self.redirectDelegate = nil
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { [session, redirectDelegate] continuation in
            var taskRef: URLSessionDataTask?
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                if let delegate = redirectDelegate,
                   let taskID = taskRef?.taskIdentifier,
                   delegate.consumeBlockedRedirect(for: taskID) {
                    continuation.resume(throwing: Concept2Error.insecureRedirectBlocked)
                } else {
                    continuation.resume(returning: (data, response))
                }
            }
            taskRef = task
            task.resume()
        }
    }
}

/// URLSession task delegate that rejects HTTP downgrade redirects.
///
/// Prevents the `Authorization` header from being sent over unencrypted
/// connections when a server responds with a redirect to `http://`.
/// Tracks blocked redirects so the transport can throw a typed error.
final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    /// Set of task identifiers for which a redirect was blocked.
    private var blockedTaskIDs = Set<Int>()

    /// Returns `true` and clears the flag if the given task had its redirect blocked.
    func consumeBlockedRedirect(for taskID: Int) -> Bool {
        lock.withLock {
            blockedTaskIDs.remove(taskID) != nil
        }
    }

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
            _ = lock.withLock { blockedTaskIDs.insert(task.taskIdentifier) }
            completionHandler(nil)
        }
    }
}
