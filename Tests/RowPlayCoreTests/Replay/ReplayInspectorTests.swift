import XCTest
@testable import RowPlayCore

final class ReplayInspectorTests: XCTestCase {
    // MARK: - distancePerStroke

    func testDistancePerStrokeReturnsNilForInvalidPace() {
        XCTAssertNil(ReplayInspector.distancePerStroke(pace: 0, cadence: 28))
    }

    func testDistancePerStrokeReturnsNilForInvalidCadence() {
        XCTAssertNil(ReplayInspector.distancePerStroke(pace: 120, cadence: 0))
    }

    func testDistancePerStrokeReturnsNilForNaN() {
        XCTAssertNil(ReplayInspector.distancePerStroke(pace: .nan, cadence: 28))
        XCTAssertNil(ReplayInspector.distancePerStroke(pace: 120, cadence: .nan))
    }

    func testDistancePerStrokeUses500mBasis() {
        let pace: TimeInterval = 120
        let cadence: Double = 28
        let dps = ReplayInspector.distancePerStroke(pace: pace, cadence: cadence)
        XCTAssertNotNil(dps)
        // 30000 / (pace * cadence) = 30000 / (120 * 28) = 30000 / 3360 ≈ 8.9286
        XCTAssertEqual(dps!, 30_000 / (pace * cadence), accuracy: 0.0001)
    }

    // MARK: - splitIndexAt

    func testSplitIndexAtReturnsNilForEmptySplits() {
        XCTAssertNil(ReplayInspector.splitIndexAt(splits: [], distance: 100))
    }

    func testSplitIndexAtMapsDistanceIntoCorrectSegment() {
        let splits = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
            Split(index: 1, distance: 500, time: 118, pace: 118)
        ]
        XCTAssertEqual(ReplayInspector.splitIndexAt(splits: splits, distance: 0), 0)
        XCTAssertEqual(ReplayInspector.splitIndexAt(splits: splits, distance: 250), 0)
        XCTAssertEqual(ReplayInspector.splitIndexAt(splits: splits, distance: 500), 0)
        XCTAssertEqual(ReplayInspector.splitIndexAt(splits: splits, distance: 501), 1)
        XCTAssertEqual(ReplayInspector.splitIndexAt(splits: splits, distance: 1000), 1)
    }
}
