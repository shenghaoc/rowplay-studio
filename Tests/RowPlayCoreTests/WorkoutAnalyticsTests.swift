import XCTest
@testable import RowPlayCore

final class WorkoutAnalyticsTests: XCTestCase {
    private func makeWorkout(
        id: Int,
        sport: Sport = .rower,
        distance: Double = 2_000,
        time: TimeInterval = 480,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Workout {
        Workout(
            id: id,
            date: date,
            sport: sport,
            distance: distance,
            time: time,
            pace: time / (distance / 500),
            workoutType: "test",
            hasStrokeData: false
        )
    }

    func testDashboardSummaryAccountsForBikeChallengeDistance() {
        let workouts = DemoWorkoutLibrary.details.map(\.workout)
        let summary = WorkoutAnalytics.dashboardSummary(for: workouts)
        let bikeDistance = workouts.filter { $0.sport == .bike }.reduce(0) { $0 + $1.distance }

        XCTAssertEqual(summary.sessions, workouts.count)
        XCTAssertEqual(summary.challengeDistance, summary.totalDistance - bikeDistance / 2, accuracy: 0.0001)
        XCTAssertEqual(summary.bySport.first?.sport, .rower)
    }

    func testDistanceBandUsesStandardDistanceTolerance() {
        XCTAssertEqual(WorkoutAnalytics.distanceBand(for: 2_003).label, "2k")
        XCTAssertEqual(WorkoutAnalytics.distanceBand(for: 8_000).label, "7k-15k")
    }

    func testLinearTrendReturnsHumanReadableDailySlope() throws {
        let start = Date(timeIntervalSince1970: 0)
        let points = [
            (x: start, y: 120.0),
            (x: start.addingTimeInterval(86_400), y: 118.0),
            (x: start.addingTimeInterval(172_800), y: 116.0)
        ]

        let fit = try XCTUnwrap(WorkoutAnalytics.linearTrend(points: points))

        XCTAssertEqual(fit.slopePerDay, -2, accuracy: 0.0001)
        XCTAssertEqual(fit.delta, -4, accuracy: 0.0001)
        XCTAssertEqual(fit.count, 3)
    }

    func testDashboardPersonalBestsUsesSuppliedPBIDs() {
        let workouts = [
            makeWorkout(id: 1, distance: 2_000, time: 420),
            makeWorkout(id: 2, distance: 2_000, time: 430),
            makeWorkout(id: 3, sport: .skierg, distance: 5_000, time: 1_100),
        ]

        let pbs = WorkoutAnalytics.dashboardPersonalBests(for: workouts, pbIds: [1, 3])

        XCTAssertEqual(pbs.map(\.id), [1, 3])
        XCTAssertEqual(pbs.map(\.sport), [.rower, .skierg])
        XCTAssertEqual(pbs.map(\.distance), [2_000, 5_000])
    }

    func testRecentPaceWorkoutsReturnsLatestMatchingSportInDateOrder() {
        let start = Date(timeIntervalSince1970: 0)
        let workouts = [
            makeWorkout(id: 1, sport: .rower, date: start.addingTimeInterval(86_400)),
            makeWorkout(id: 2, sport: .skierg, date: start.addingTimeInterval(172_800)),
            makeWorkout(id: 3, sport: .rower, date: start.addingTimeInterval(259_200)),
            makeWorkout(id: 4, sport: .rower, date: start.addingTimeInterval(345_600)),
        ]

        let recent = WorkoutAnalytics.recentPaceWorkouts(for: workouts, sport: .rower, limit: 2)

        XCTAssertEqual(recent.map(\.id), [3, 4])
    }
}
