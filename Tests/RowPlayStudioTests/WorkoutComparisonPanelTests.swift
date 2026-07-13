import XCTest
@testable import RowPlayStudio

@MainActor
final class WorkoutComparisonPanelTests: XCTestCase {
    func testAlignmentPreservesExistingComparisonSelection() {
        let selection = WorkoutComparisonPanel.alignedCandidateID(
            current: 42,
            candidateIDs: [7, 42, 99]
        )

        XCTAssertEqual(selection, 42)
    }

    func testAlignmentFallsBackWhenComparisonDisappears() {
        let selection = WorkoutComparisonPanel.alignedCandidateID(
            current: 42,
            candidateIDs: [7, 99]
        )

        XCTAssertEqual(selection, 7)
    }

    func testPaceChartDomainMakesFasterPacesPlotHigher() {
        let domain = WorkoutComparisonPanel.paceChartDomain(for: [120, 90])

        XCTAssertTrue(domain.contains(-120))
        XCTAssertTrue(domain.contains(-90))
        XCTAssertGreaterThan(-90, -120)
        XCTAssertFalse(domain.contains(0))
    }

    func testPaceChartDomainFallsBackForInvalidInput() {
        XCTAssertEqual(
            WorkoutComparisonPanel.paceChartDomain(for: [.nan, .infinity, 0]),
            -180 ... -60
        )
    }
}
