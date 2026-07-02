import XCTest
@testable import RowPlayCore

final class PersonalBestsTests: XCTestCase {
    private func makeWorkout(
        id: Int, sport: Sport, distance: Double, time: TimeInterval,
        date: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> Workout {
        Workout(
            id: id, date: date, sport: sport, distance: distance,
            time: time, pace: time / (distance / 500),
            workoutType: "test", hasStrokeData: false
        )
    }

    // MARK: - distancePBs

    func testDistancePBsReturnsFastestPerDistance() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 480),
            makeWorkout(id: 2, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 3, sport: .rower, distance: 5000, time: 1200),
        ]
        let pbs = PersonalBests.distancePBs(for: workouts)

        let pb2k = pbs.first { $0.distance == 2000 }
        XCTAssertNotNil(pb2k)
        XCTAssertEqual(pb2k?.time, 420)
    }

    func testDistancePBsRespectsTolerance() {
        // 2003m is within 2% of 2000m
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2003, time: 420),
            makeWorkout(id: 2, sport: .rower, distance: 1997, time: 430),
        ]
        let pbs = PersonalBests.distancePBs(for: workouts)

        let pb2k = pbs.first { $0.distance == 2000 }
        XCTAssertNotNil(pb2k)
        XCTAssertEqual(pb2k?.time, 420)
    }

    func testDistancePBsSkipsZeroTime() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 0),
        ]
        let pbs = PersonalBests.distancePBs(for: workouts)
        XCTAssertNil(pbs.first { $0.distance == 2000 })
    }

    func testDistancePBsFiltersBySport() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 2, sport: .skierg, distance: 2000, time: 400),
        ]
        let rowerPBs = PersonalBests.distancePBs(for: workouts, sport: .rower)
        let pb2k = rowerPBs.first { $0.distance == 2000 }
        XCTAssertEqual(pb2k?.time, 420)
    }

    func testDistancePBsPicksFastestAcrossSportsWhenUnfiltered() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 2, sport: .skierg, distance: 2000, time: 400),
        ]
        let pbs = PersonalBests.distancePBs(for: workouts)

        let pb2k = pbs.filter { $0.distance == 2000 }
        XCTAssertEqual(pb2k.count, 1)
        XCTAssertEqual(pb2k.first?.time, 400)
        XCTAssertEqual(pb2k.first?.sport, .skierg)
    }

    func testDistancePBsReturnsAllStandardDistances() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 500, time: 90),
            makeWorkout(id: 2, sport: .rower, distance: 1000, time: 200),
            makeWorkout(id: 3, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 4, sport: .rower, distance: 5000, time: 1200),
            makeWorkout(id: 5, sport: .rower, distance: 6000, time: 1500),
            makeWorkout(id: 6, sport: .rower, distance: 10000, time: 2520),
            makeWorkout(id: 7, sport: .rower, distance: 21097, time: 5400),
        ]
        let pbs = PersonalBests.distancePBs(for: workouts)
        XCTAssertEqual(pbs.count, 7)
    }

    // MARK: - pbWorkoutIds

    func testPbWorkoutIdsReturnsCorrectIDs() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 480),
            makeWorkout(id: 2, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 3, sport: .rower, distance: 5000, time: 1200),
        ]
        let ids = PersonalBests.pbWorkoutIds(for: workouts)
        XCTAssertTrue(ids.contains(2))
        XCTAssertTrue(ids.contains(3))
        XCTAssertFalse(ids.contains(1))
    }

    func testPbWorkoutIdsHandlesEmptyWorkouts() {
        let ids = PersonalBests.pbWorkoutIds(for: [])
        XCTAssertTrue(ids.isEmpty)
    }

    func testPbWorkoutIdsPicksFastestAcrossSportsWhenUnfiltered() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 2, sport: .skierg, distance: 2000, time: 400),
        ]
        let ids = PersonalBests.pbWorkoutIds(for: workouts)

        XCTAssertEqual(ids, [2])
    }

    func testPbWorkoutIdsFiltersBySport() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2000, time: 420),
            makeWorkout(id: 2, sport: .skierg, distance: 2000, time: 400),
        ]
        let ids = PersonalBests.pbWorkoutIds(for: workouts, sport: .rower)

        XCTAssertEqual(ids, [1])
    }

    func testStandardDistanceMatchesWithinTolerance() {
        XCTAssertEqual(PersonalBests.standardDistance(matching: 2_003), 2_000)
        XCTAssertNil(PersonalBests.standardDistance(matching: 1_700))
    }
}
