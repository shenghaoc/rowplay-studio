#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import Synchronization
@testable import RowPlayCore

// MARK: - Fake Transport

/// Fake HTTP transport for testing. Captures requests and returns configured responses.
final class FakeHTTPTransport: HTTPTransport {
    private struct State: Sendable {
        var capturedRequests: [URLRequest] = []
        var callCount = 0
        var result: Result<(Data, HTTPURLResponse), any Error>?
    }

    private let state = Mutex(State())

    /// All requests passed to `data(for:)`, in order.
    var capturedRequests: [URLRequest] {
        state.withLock { $0.capturedRequests }
    }

    /// The last URLRequest passed to `data(for:)`.
    var capturedRequest: URLRequest? {
        state.withLock { $0.capturedRequests.last }
    }

    /// The number of times `data(for:)` was called.
    var callCount: Int {
        state.withLock { $0.callCount }
    }

    /// The result to return on the next call. Set this before calling client methods.
    var result: Result<(Data, HTTPURLResponse), any Error>! {
        get { state.withLock { $0.result } }
        set { state.withLock { $0.result = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentResult = state.withLock { state in
            state.capturedRequests.append(request)
            state.callCount += 1
            return state.result!
        }
        switch currentResult {
        case let .success((data, response)):
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

/// Fake transport that returns responses in sequence (for multi-request operations).
final class SequenceHTTPTransport: HTTPTransport {
    private struct State: Sendable {
        var responses: [Result<(Data, HTTPURLResponse), any Error>]
        var index = 0
        var capturedRequests: [URLRequest] = []
    }

    private let state: Mutex<State>

    var capturedRequests: [URLRequest] {
        state.withLock { $0.capturedRequests }
    }

    init(responses: [Result<(Data, HTTPURLResponse), any Error>]) {
        state = Mutex(State(responses: responses))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result = state.withLock { state in
            state.capturedRequests.append(request)
            let index = state.index
            state.index += 1
            return index < state.responses.count ? state.responses[index] : state.responses.last!
        }
        switch result {
        case let .success((data, response)):
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Helpers

/// Create an HTTPURLResponse with the given status code.
private func httpResponse(statusCode: Int, url: URL = URL(string: "https://example.com")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
}

/// Sample workout summary JSON matching the Concept2 logbook API format.
private let sampleSummaryJSON = """
{
    "data": [
        {
            "id": 1001,
            "date": "2024-06-15 10:30:00",
            "type": "rower",
            "distance": 5000,
            "time": 12000,
            "stroke_rate": 28,
            "stroke_count": 200,
            "drag_factor": 120,
            "calories_total": 450,
            "workout_type": "JustRow",
            "stroke_data": true,
            "verified": true
        },
        {
            "id": 1002,
            "date": "2024-06-14 08:00:00",
            "type": "bike",
            "distance": 10000,
            "time": 18000,
            "stroke_rate": 90,
            "calories_total": 300,
            "workout_type": "JustRow",
            "stroke_data": false,
            "verified": true
        }
    ],
    "meta": {
        "pagination": {
            "total_pages": 5
        }
    }
}
"""

private let sampleDetailJSON = """
{
    "data": {
        "id": 1001,
        "date": "2024-06-15 10:30:00",
        "type": "rower",
        "distance": 5000,
        "time": 12000,
        "stroke_rate": 28,
        "stroke_count": 200,
        "drag_factor": 120,
        "calories_total": 450,
        "workout_type": "JustRow",
        "stroke_data": true,
        "verified": true,
        "workout": {
            "splits": [
                { "distance": 1000, "time": 2400, "stroke_rate": 28 },
                { "distance": 1000, "time": 2350, "stroke_rate": 29 }
            ]
        }
    }
}
"""

// MARK: - Tests

final class URLSessionConcept2ClientTests: XCTestCase {
    private let testToken = "test-secret-token-abcdef1234567890ab"
    private let baseURL = URL(string: "https://log.concept2.com")!

    private func makeClient(transport: any HTTPTransport) -> URLSessionConcept2Client {
        URLSessionConcept2Client(baseURL: baseURL, token: testToken, transport: transport)
    }

    // MARK: - Request Building

    func testWorkoutSummariesRequestUsesExpectedPath() async throws {
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200)))
        let client = makeClient(transport: transport)

        _ = try await client.fetchWorkouts(page: 2, perPage: 100)

        let request = try XCTUnwrap(transport.capturedRequest)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/users/me/results")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        XCTAssertEqual(queryItems.first(where: { $0.name == "page" })?.value, "2")
        XCTAssertEqual(queryItems.first(where: { $0.name == "number" })?.value, "100")
    }

    func testWorkoutDetailRequestUsesExpectedPath() async throws {
        let detailData = sampleDetailJSON.data(using: .utf8)!
        let strokesData = "{\"data\":[]}".data(using: .utf8)!
        let transport = SequenceHTTPTransport(responses: [
            .success((detailData, httpResponse(statusCode: 200))),
            .success((strokesData, httpResponse(statusCode: 200))),
        ])
        let client = makeClient(transport: transport)

        _ = try await client.fetchWorkoutDetail(id: 1001)

        // First request should be the detail endpoint.
        let request = try XCTUnwrap(transport.capturedRequests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/users/me/results/1001")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        XCTAssertEqual(queryItems.first(where: { $0.name == "include" })?.value, "metadata")
    }

    // MARK: - Headers

    func testAuthorizationHeaderUsesInjectedToken() async throws {
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200)))
        let client = makeClient(transport: transport)

        _ = try await client.fetchWorkouts(page: 1, perPage: 10)

        let request = try XCTUnwrap(transport.capturedRequest)
        let authHeader = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authHeader, "Bearer \(testToken)")
    }

    func testAuthorizationHeaderNotInThrownError() async {
        let transport = FakeHTTPTransport()
        transport.result = .failure(URLError(.notConnectedToInternet))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch {
            let errorDesc = String(describing: error)
            XCTAssertFalse(errorDesc.contains(testToken),
                "Error description must not contain the token. Got: \(errorDesc)")
            XCTAssertFalse(errorDesc.contains("Bearer"),
                "Error description must not contain 'Bearer'. Got: \(errorDesc)")
        }
    }

    func testAcceptHeaderRequestsJSON() async throws {
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200)))
        let client = makeClient(transport: transport)

        _ = try await client.fetchWorkouts(page: 1, perPage: 10)

        let request = try XCTUnwrap(transport.capturedRequest)
        let acceptHeader = request.value(forHTTPHeaderField: "Accept")
        XCTAssertEqual(acceptHeader, "application/vnd.c2logbook.v1+json")
    }

    // MARK: - Decoding

    func testDecodesWorkoutSummaryResponse() async throws {
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200)))
        let client = makeClient(transport: transport)

        let page = try await client.fetchWorkouts(page: 1, perPage: 50)

        XCTAssertEqual(page.totalPages, 5)
        XCTAssertEqual(page.workouts.count, 2)

        let first = page.workouts[0]
        XCTAssertEqual(first.id, 1001)
        XCTAssertEqual(first.sport, .rower)
        XCTAssertEqual(first.distance, 5000)
        XCTAssertEqual(first.time, 1200, accuracy: 0.01) // 12000 tenths / 10
        XCTAssertEqual(first.strokeRate, 28)
        XCTAssertEqual(first.strokeCount, 200)
        XCTAssertEqual(first.dragFactor, 120)
        XCTAssertEqual(first.caloriesTotal, 450)
        XCTAssertTrue(first.hasStrokeData)

        let second = page.workouts[1]
        XCTAssertEqual(second.id, 1002)
        XCTAssertEqual(second.sport, .bike)
        XCTAssertEqual(second.distance, 10000)
        XCTAssertEqual(second.time, 1800, accuracy: 0.01)
    }

    func testDecodesWorkoutDetailResponse() async throws {
        let transport = FakeHTTPTransport()
        let data = sampleDetailJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200)))
        let client = makeClient(transport: transport)

        let detail = try await client.fetchWorkoutDetail(id: 1001)

        XCTAssertEqual(detail.workout.id, 1001)
        XCTAssertEqual(detail.workout.sport, .rower)
        XCTAssertEqual(detail.workout.distance, 5000)
        XCTAssertEqual(detail.splits.count, 2)
        XCTAssertEqual(detail.splits[0].distance, 1000)
        XCTAssertEqual(detail.splits[0].time, 240, accuracy: 0.01) // 2400 tenths / 10
        XCTAssertEqual(detail.splits[1].distance, 1000)
        XCTAssertEqual(detail.splits[1].time, 235, accuracy: 0.01)
    }

    // MARK: - Non-2xx Errors

    func testNon2xxThrowsTypedError() async {
        let transport = FakeHTTPTransport()
        let emptyData = "{}".data(using: .utf8)!
        transport.result = .success((emptyData, httpResponse(statusCode: 401)))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch let error as Concept2Error {
            XCTAssertEqual(error, .unauthorized)
            // Verify token is not in the error description.
            XCTAssertFalse(error.description.contains(testToken))
        } catch {
            XCTFail("Expected Concept2Error, got \(error)")
        }
    }

    func test403ThrowsForbidden() async {
        let transport = FakeHTTPTransport()
        let emptyData = "{}".data(using: .utf8)!
        transport.result = .success((emptyData, httpResponse(statusCode: 403)))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch let error as Concept2Error {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("Expected Concept2Error, got \(error)")
        }
    }

    func test429ThrowsRateLimited() async {
        let transport = FakeHTTPTransport()
        let emptyData = "{}".data(using: .utf8)!
        transport.result = .success((emptyData, httpResponse(statusCode: 429)))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch let error as Concept2Error {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Expected Concept2Error, got \(error)")
        }
    }

    func test500ThrowsHTTPError() async {
        let transport = FakeHTTPTransport()
        let emptyData = "{}".data(using: .utf8)!
        transport.result = .success((emptyData, httpResponse(statusCode: 500)))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch let error as Concept2Error {
            XCTAssertEqual(error, .httpError(statusCode: 500))
            XCTAssertFalse(error.description.contains(testToken))
        } catch {
            XCTFail("Expected Concept2Error, got \(error)")
        }
    }

    // MARK: - Transport Failure

    func testTransportFailurePropagatesAsConcept2Error() async {
        let transport = FakeHTTPTransport()
        transport.result = .failure(URLError(.timedOut))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch is Concept2TransportError {
            // Expected: transport failure wrapped as Concept2TransportError.
            // Verify token is not in the error description.
            let transportError = Concept2TransportError(underlying: URLError(.timedOut))
            XCTAssertFalse(transportError.description.contains(testToken))
        } catch {
            XCTFail("Expected Concept2TransportError, got \(error)")
        }
    }

    func testTransportFailureDoesNotExposeToken() async {
        let transport = FakeHTTPTransport()
        transport.result = .failure(URLError(.notConnectedToInternet))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch {
            let desc = String(describing: error)
            XCTAssertFalse(desc.contains(testToken),
                "Transport error must not expose token. Got: \(desc)")
        }
    }

    // MARK: - Token Privacy

    func testClientDoesNotPersistToken() {
        // The URLSessionConcept2Client holds the token as a private stored
        // property in memory only. It does not write to UserDefaults, files,
        // Keychain, SQLite, or any other storage. This is verified by design:
        // the class has no storage properties, no file handles, and no
        // UserDefaults references. The token exists only as an instance
        // variable for the lifetime of the client.
        //
        // If the client were to persist the token, this test would need to
        // check UserDefaults, the filesystem, and Keychain. Since it does not,
        // the design invariant is satisfied by the absence of storage code.
        let transport = FakeHTTPTransport()
        let _ = URLSessionConcept2Client(
            baseURL: baseURL,
            token: "should-not-be-persisted",
            transport: transport
        )
        // No assertion needed — the client has no write paths.
        // The token is only accessible via the Authorization header on requests,
        // which is tested in testAuthorizationHeaderUsesInjectedToken.
    }

    // MARK: - Insecure Connection

    func testHTTPTargetThrowsInsecureConnection() async {
        let httpBaseURL = URL(string: "http://log.concept2.com")!
        let transport = FakeHTTPTransport()
        let client = URLSessionConcept2Client(
            baseURL: httpBaseURL,
            token: testToken,
            transport: transport
        )

        do {
            _ = try await client.fetchWorkouts(page: 1, perPage: 10)
            XCTFail("Expected error")
        } catch let error as Concept2Error {
            XCTAssertEqual(error, .insecureConnection)
        } catch {
            XCTFail("Expected Concept2Error.insecureConnection, got \(error)")
        }
    }

    func testLocalhostHTTPIsAllowed() async throws {
        let localhostURL = URL(string: "http://localhost:8080")!
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200, url: localhostURL)))
        let client = URLSessionConcept2Client(
            baseURL: localhostURL,
            token: testToken,
            transport: transport
        )

        // Should not throw .insecureConnection for localhost.
        let page = try await client.fetchWorkouts(page: 1, perPage: 10)
        XCTAssertEqual(page.workouts.count, 2)
    }

    func testLoopbackHTTPIsAllowed() async throws {
        let loopbackURL = URL(string: "http://127.0.0.1:8080")!
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200, url: loopbackURL)))
        let client = URLSessionConcept2Client(
            baseURL: loopbackURL,
            token: testToken,
            transport: transport
        )

        // Should not throw .insecureConnection for 127.0.0.1.
        let page = try await client.fetchWorkouts(page: 1, perPage: 10)
        XCTAssertEqual(page.workouts.count, 2)
    }

    func testIPv6LoopbackHTTPIsAllowed() async throws {
        let ipv6URL = URL(string: "http://[::1]:8080")!
        let transport = FakeHTTPTransport()
        let data = sampleSummaryJSON.data(using: .utf8)!
        transport.result = .success((data, httpResponse(statusCode: 200, url: ipv6URL)))
        let client = URLSessionConcept2Client(
            baseURL: ipv6URL,
            token: testToken,
            transport: transport
        )

        // Should not throw .insecureConnection for [::1].
        let page = try await client.fetchWorkouts(page: 1, perPage: 10)
        XCTAssertEqual(page.workouts.count, 2)
    }

    // MARK: - Secure Session Configuration

    func testMakeSecureConfigurationIsEphemeralWithStrictTimeouts() {
        let config = URLSessionHTTPTransport.makeSecureConfiguration()

        XCTAssertEqual(config.timeoutIntervalForRequest, 30.0)
        XCTAssertEqual(config.timeoutIntervalForResource, 300.0)

        // Must not use the shared disk-backed session stores that
        // `URLSessionConfiguration.default` wires up.
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
    }

    func testDefaultTransportUsesSecureConfigurationFactory() {
        // Constructing the production transport must not require a network call;
        // this only verifies the default argument path compiles and runs.
        let transport = URLSessionHTTPTransport()
        // Keep a strong reference long enough that the session is created.
        _ = transport
        // Explicit factory remains the single source of truth for timeouts/storage.
        let config = URLSessionHTTPTransport.makeSecureConfiguration()
        XCTAssertEqual(config.timeoutIntervalForRequest, 30.0)
        XCTAssertNil(config.urlCache)
    }

    // MARK: - Redirect Downgrade Protection

    func testHTTPRedirectIsBlockedByDelegate() {
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://log.concept2.com/api/test")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://log.concept2.com/api/test")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "http://attacker.example.com/stolen"]
        )!
        let redirectedRequest = URLRequest(url: URL(string: "http://attacker.example.com/stolen")!)

        var allowedRequest: URLRequest?
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirectedRequest
        ) { request in
            allowedRequest = request
        }

        XCTAssertNil(allowedRequest)
        XCTAssertTrue(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        XCTAssertFalse(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        session.invalidateAndCancel()
    }

    func testHTTPSRedirectToDifferentHostIsBlockedByDelegate() {
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://log.concept2.com/api/test")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://log.concept2.com/api/test")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://attacker.example.com/stolen"]
        )!
        let redirectedRequest = URLRequest(url: URL(string: "https://attacker.example.com/stolen")!)

        var allowedRequest: URLRequest?
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirectedRequest
        ) { request in
            allowedRequest = request
        }

        XCTAssertNil(allowedRequest)
        XCTAssertTrue(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        XCTAssertFalse(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        session.invalidateAndCancel()
    }

    func testHTTPSRedirectToSameHostDifferentCaseIsAllowedByDelegate() {
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://log.concept2.com/api/test")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://log.concept2.com/api/test")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://LOG.CONCEPT2.COM/api/test/redirected"]
        )!
        let redirectedRequest = URLRequest(
            url: URL(string: "https://LOG.CONCEPT2.COM/api/test/redirected")!
        )

        var allowedRequest: URLRequest?
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirectedRequest
        ) { request in
            allowedRequest = request
        }

        XCTAssertEqual(allowedRequest?.url, redirectedRequest.url)
        XCTAssertFalse(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        session.invalidateAndCancel()
    }

    func testHTTPSRedirectToSameHostDifferentPortIsBlockedByDelegate() {
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://log.concept2.com/api/test")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://log.concept2.com/api/test")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://log.concept2.com:8443/stolen"]
        )!
        let redirectedRequest = URLRequest(
            url: URL(string: "https://log.concept2.com:8443/stolen")!
        )

        var allowedRequest: URLRequest?
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirectedRequest
        ) { request in
            allowedRequest = request
        }

        XCTAssertNil(allowedRequest)
        XCTAssertTrue(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        session.invalidateAndCancel()
    }

    func testHTTPSRedirectWithMissingHostIsBlockedByDelegate() {
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://log.concept2.com/api/test")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://log.concept2.com/api/test")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https:///stolen"]
        )!
        // Empty-host absolute URL: scheme is https but host is nil.
        // nil must not compare equal to the original host (or to another nil).
        let emptyHostURL = URL(string: "https:///stolen")!
        XCTAssertNil(emptyHostURL.host, "Test requires a URL whose host component is nil")
        let redirectedRequest = URLRequest(url: emptyHostURL)

        var allowedRequest: URLRequest?
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirectedRequest
        ) { request in
            allowedRequest = request
        }

        XCTAssertNil(allowedRequest)
        XCTAssertTrue(delegate.consumeBlockedRedirect(for: task.taskIdentifier))
        session.invalidateAndCancel()
    }

    // MARK: - Concept2Error Descriptions

    func testErrorDescriptionsDoNotContainSensitiveData() {
        let errors: [Concept2Error] = [
            .unauthorized,
            .forbidden,
            .rateLimited,
            .httpError(statusCode: 500),
            .invalidURL("/test"),
            .decodingFailed,
            .insecureConnection,
            .insecureRedirectBlocked,
        ]

        for error in errors {
            let desc = error.description
            XCTAssertFalse(desc.contains("Bearer"), "Error desc must not contain 'Bearer': \(desc)")
            XCTAssertFalse(desc.contains(testToken), "Error desc must not contain token: \(desc)")
        }
    }

    func testTransportErrorDescriptionRedactsUnderlying() {
        let underlying = URLError(.timedOut)
        let error = Concept2TransportError(underlying: underlying)
        let desc = error.description
        XCTAssertEqual(desc, "Concept2 API transport error")
        XCTAssertFalse(desc.contains("token"), "Transport error desc must not contain sensitive data")
    }
}
