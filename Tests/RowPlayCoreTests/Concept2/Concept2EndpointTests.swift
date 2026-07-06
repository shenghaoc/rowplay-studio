import XCTest
@testable import RowPlayCore

final class Concept2EndpointTests: XCTestCase {
    private let baseURL = URL(string: "https://log.concept2.com")!

    // MARK: - Workout Summaries

    func testWorkoutSummariesPath() throws {
        let endpoint = Concept2Endpoint.workoutSummaries(page: 1, number: 50)
        let url = try endpoint.url(from: baseURL)
        XCTAssertEqual(url.path, "/api/users/me/results")
    }

    func testWorkoutSummariesPagination() throws {
        let endpoint = Concept2Endpoint.workoutSummaries(page: 3, number: 250)
        let url = try endpoint.url(from: baseURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(queryItems.first(where: { $0.name == "page" })?.value, "3")
        XCTAssertEqual(queryItems.first(where: { $0.name == "number" })?.value, "250")
    }

    // MARK: - Workout Detail

    func testWorkoutDetailPath() throws {
        let endpoint = Concept2Endpoint.workoutDetail(id: 12345)
        let url = try endpoint.url(from: baseURL)
        XCTAssertEqual(url.path, "/api/users/me/results/12345")
    }

    func testWorkoutDetailIncludesMetadataParam() throws {
        let endpoint = Concept2Endpoint.workoutDetail(id: 999)
        let url = try endpoint.url(from: baseURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(queryItems.first(where: { $0.name == "include" })?.value, "metadata")
    }

    // MARK: - Base URL

    func testBaseURLPreserved() throws {
        let customBase = URL(string: "https://custom.example.com")!
        let endpoint = Concept2Endpoint.workoutSummaries(page: 1, number: 10)
        let url = try endpoint.url(from: customBase)
        XCTAssertEqual(url.host, "custom.example.com")
    }

    func testFullURLConstruction() throws {
        let endpoint = Concept2Endpoint.workoutSummaries(page: 2, number: 100)
        let url = try endpoint.url(from: baseURL)
        XCTAssertEqual(url.absoluteString, "https://log.concept2.com/api/users/me/results?page=2&number=100")
    }

    func testBaseURLWithPathPrefixIsPreserved() throws {
        let customBase = URL(string: "https://gateway.example.com/api/v1")!
        let endpoint = Concept2Endpoint.workoutSummaries(page: 1, number: 10)
        let url = try endpoint.url(from: customBase)
        XCTAssertEqual(url.path, "/api/v1/api/users/me/results")
    }
}
