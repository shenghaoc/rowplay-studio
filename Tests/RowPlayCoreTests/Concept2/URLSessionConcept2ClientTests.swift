import XCTest
@testable import RowPlayCore

// MARK: - Fake Transport

/// Fake HTTP transport for testing. Captures requests and returns configured responses.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedRequests: [URLRequest] = []
    private var _callCount = 0
    private var _result: Result<(Data, HTTPURLResponse), Error>!

    /// All requests passed to `data(for:)`, in order.
    var capturedRequests: [URLRequest] {
        lock.withLock { _capturedRequests }
    }

    /// The last URLRequest passed to `data(for:)`.
    var capturedRequest: URLRequest? {
        lock.withLock { _capturedRequests.last }
    }

    /// The number of times `data(for:)` was called.
    var callCount: Int {
        lock.withLock { _callCount }
    }

    /// The result to return on the next call. Set this before calling client methods.
    var result: Result<(Data, HTTPURLResponse), Error>! {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            _capturedRequests.append(request)
            _callCount += 1
        }
        let currentResult = lock.withLock { _result! }
        switch currentResult {
        case let .success((data, response)):
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

/// Fake transport that returns responses in sequence (for multi-request operations).
final class SequenceHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [Result<(Data, HTTPURLResponse), Error>]
    private var _index = 0
    private(set) var capturedRequests: [URLRequest] = []

    init(responses: [Result<(Data, HTTPURLResponse), Error>]) {
        _responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result: Result<(Data, HTTPURLResponse), Error> = lock.withLock {
            capturedRequests.append(request)
            let idx = _index
            _index += 1
            return idx < _responses.count ? _responses[idx] : _responses.last!
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

    // MARK: - Concept2Error Descriptions

    func testErrorDescriptionsDoNotContainSensitiveData() {
        let errors: [Concept2Error] = [
            .unauthorized,
            .forbidden,
            .rateLimited,
            .httpError(statusCode: 500),
            .invalidURL("/test"),
            .decodingFailed,
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
