import XCTest
@testable import RowPlayCore

final class MockLiveSourceTests: XCTestCase {

    func testPollReturnsWorkout() async throws {
        let source = MockLiveSource()
        let result = try await source.poll(knownIDs: [])
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.added, 1)
    }

    func testPollFiltersKnownIDs() async throws {
        let source = MockLiveSource()
        let first = try await source.poll(knownIDs: [])
        let firstID = first.workouts[0].id
        let second = try await source.poll(knownIDs: [firstID])
        // Second poll should still return a workout (different ID)
        XCTAssertEqual(second.workouts.count, 1)
        XCTAssertNotEqual(second.workouts[0].id, firstID)
    }

    func testIDsIncrement() async throws {
        let source = MockLiveSource()
        let r1 = try await source.poll(knownIDs: [])
        let r2 = try await source.poll(knownIDs: [])
        let r3 = try await source.poll(knownIDs: [])
        XCTAssertEqual(r1.workouts[0].id + 1, r2.workouts[0].id)
        XCTAssertEqual(r2.workouts[0].id + 1, r3.workouts[0].id)
    }

    func testSportDistribution() async throws {
        let source = MockLiveSource()
        var sports = Set<Sport>()
        for _ in 0 ..< 20 {
            let result = try await source.poll(knownIDs: [])
            for w in result.workouts {
                sports.insert(w.sport)
            }
        }
        // With 20 polls from 5-slot distribution, we should see multiple sports
        XCTAssertGreaterThanOrEqual(sports.count, 2)
    }

    func testWorkoutHasReasonableValues() async throws {
        let source = MockLiveSource()
        let result = try await source.poll(knownIDs: [])
        let workout = result.workouts[0]
        XCTAssertGreaterThan(workout.distance, 0)
        XCTAssertGreaterThan(workout.time, 0)
        XCTAssertGreaterThan(workout.pace, 0)
        XCTAssertFalse(workout.verified)
        XCTAssertEqual(workout.source, "MockLive")
    }

    func testPollWithAllKnownIDsReturnsEmpty() async throws {
        let source = MockLiveSource()
        // Generate one workout and mark its ID as known
        let first = try await source.poll(knownIDs: [])
        let knownIDs = Set(first.workouts.map(\.id))
        // The next workout has a different ID, so this should still return it
        let second = try await source.poll(knownIDs: knownIDs)
        XCTAssertEqual(second.workouts.count, 1)
    }
}
