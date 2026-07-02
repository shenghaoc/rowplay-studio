import XCTest
@testable import RowPlayCore

final class WorkoutAnalyticsTests: XCTestCase {
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
}

