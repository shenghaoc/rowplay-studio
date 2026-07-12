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
}
