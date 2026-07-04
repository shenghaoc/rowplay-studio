import XCTest
@testable import RowPlayCore

final class Concept2ClientTests: XCTestCase {
    private var client: MockConcept2Client!

    override func setUp() {
        super.setUp()
        client = MockConcept2Client()
    }

    override func tearDown() {
        client = nil
        super.tearDown()
    }

    // MARK: - fetchWorkouts

    func testFetchWorkoutsReturnsAllDemoData() async throws {
        let page = try await client.fetchWorkouts(page: 1, perPage: 100)
        XCTAssertEqual(page.workouts.count, DemoWorkoutLibrary.details.count)
        XCTAssertEqual(page.totalPages, 1)
    }

    func testFetchWorkoutsReturnsSortedByDateDescending() async throws {
        let page = try await client.fetchWorkouts(page: 1, perPage: 100)
        let dates = page.workouts.map(\.date)
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1],
                "Workouts should be sorted newest-first")
        }
    }

    func testFetchWorkoutsPagination() async throws {
        let perPage = 5
        let page1 = try await client.fetchWorkouts(page: 1, perPage: perPage)
        let page2 = try await client.fetchWorkouts(page: 2, perPage: perPage)

        XCTAssertTrue(page1.totalPages >= 2, "Should have multiple pages with perPage=5")
        XCTAssertEqual(page1.workouts.count, perPage)
        // Page 1 and page 2 should have different workouts.
        let page1Ids = Set(page1.workouts.map(\.id))
        let page2Ids = Set(page2.workouts.map(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids), "Pages should not overlap")
    }

    func testFetchWorkoutsBeyondLastPageReturnsEmpty() async throws {
        let page = try await client.fetchWorkouts(page: 999, perPage: 5)
        XCTAssertTrue(page.workouts.isEmpty)
    }

    func testFetchWorkoutsPageOneClamped() async throws {
        // Page 0 should clamp to page 1.
        let page = try await client.fetchWorkouts(page: 0, perPage: 100)
        XCTAssertEqual(page.workouts.count, DemoWorkoutLibrary.details.count)
    }

    func testFetchWorkoutsZeroPerPageReturnsEmpty() async throws {
        let page = try await client.fetchWorkouts(page: 1, perPage: 0)
        XCTAssertTrue(page.workouts.isEmpty)
        XCTAssertEqual(page.totalPages, 1, "Invalid perPage should return consistent totalPages")
    }

    func testFetchWorkoutsNegativePerPageReturnsEmpty() async throws {
        let page = try await client.fetchWorkouts(page: 1, perPage: -5)
        XCTAssertTrue(page.workouts.isEmpty)
        XCTAssertEqual(page.totalPages, 1, "Invalid perPage should return consistent totalPages")
    }

    func testFetchWorkoutsTracksCallCount() async throws {
        _ = try await client.fetchWorkouts(page: 1, perPage: 10)
        _ = try await client.fetchWorkouts(page: 2, perPage: 10)
        _ = try await client.fetchWorkouts(page: 1, perPage: 10)
        XCTAssertEqual(client.fetchWorkoutsCallCount, 3)
    }

    // MARK: - fetchWorkoutDetail

    func testFetchWorkoutDetailReturnsMatchingDetail() async throws {
        let expected = DemoWorkoutLibrary.details[0]
        let detail = try await client.fetchWorkoutDetail(id: expected.workout.id)
        XCTAssertEqual(detail.workout.id, expected.workout.id)
        XCTAssertEqual(detail.workout.sport, expected.workout.sport)
    }

    func testFetchWorkoutDetailTracksRequestedIDs() async throws {
        _ = try await client.fetchWorkoutDetail(id: 1001)
        _ = try await client.fetchWorkoutDetail(id: 1002)
        XCTAssertEqual(client.fetchDetailRequestedIDs, [1001, 1002])
    }

    func testFetchWorkoutDetailThrowsForMissingID() async {
        do {
            _ = try await client.fetchWorkoutDetail(id: 99999)
            XCTFail("Should throw for missing workout ID")
        } catch let error as Concept2ClientError {
            XCTAssertEqual(error, .workoutNotFound(99999))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Concept2Page

    func testConcept2PageEquality() {
        let page1 = Concept2Page(workouts: [], totalPages: 1)
        let page2 = Concept2Page(workouts: [], totalPages: 1)
        XCTAssertEqual(page1, page2)
    }

    func testConcept2PageInequalityDifferentPages() {
        let page1 = Concept2Page(workouts: [], totalPages: 1)
        let page2 = Concept2Page(workouts: [], totalPages: 2)
        XCTAssertNotEqual(page1, page2)
    }
}
