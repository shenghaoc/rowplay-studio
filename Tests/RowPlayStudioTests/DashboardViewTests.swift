import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class DashboardViewTests: XCTestCase {
    func testSportSummaryAccessibilityValueUsesSelectedDistanceUnit() {
        let summary = SportSummary(
            sport: .rower,
            sessions: 2,
            distance: 5_000,
            time: 1_200,
            averagePace: 120,
            bestPace: 118,
            longestDistance: 5_000
        )

        let value = DashboardView.sportSummaryAccessibilityValue(summary, unit: .imperial)

        XCTAssertTrue(value.contains("3.11 mi"))
    }
}
