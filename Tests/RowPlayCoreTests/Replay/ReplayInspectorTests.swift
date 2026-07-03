import XCTest
@testable import RowPlayCore

final class ReplayInspectorTests: XCTestCase {
    // MARK: - distancePerStroke

    func testDistancePerStrokeReturnsNilForInvalidPace() {
        XCTAssertNil(ReplayInspector.distancePerStroke(sport: .rower, pace: 0, cadence: 28))
    }

    func testDistancePerStrokeReturnsNilForInvalidCadence() {
        XCTAssertNil(ReplayInspector.distancePerStroke(sport: .rower, pace: 120, cadence: 0))
    }

    func testDistancePerStrokeReturnsNilForNaN() {
        XCTAssertNil(ReplayInspector.distancePerStroke(sport: .rower, pace: .nan, cadence: 28))
        XCTAssertNil(ReplayInspector.distancePerStroke(sport: .rower, pace: 120, cadence: .nan))
    }

    func testDistancePerStrokeRowerUses500mBasis() {
        let pace: TimeInterval = 120
        let cadence: Double = 28
        let dps = ReplayInspector.distancePerStroke(sport: .rower, pace: pace, cadence: cadence)
        XCTAssertNotNil(dps)
        // 30000 / (pace * cadence) = 30000 / (120 * 28) = 30000 / 3360 ≈ 8.9286
        XCTAssertEqual(dps!, 30_000 / (pace * cadence), accuracy: 0.0001)
    }

    func testDistancePerStrokeSkiErgUses500mBasis() {
        let pace: TimeInterval = 120
        let cadence: Double = 28
        let dps = ReplayInspector.distancePerStroke(sport: .skierg, pace: pace, cadence: cadence)
        XCTAssertNotNil(dps)
        XCTAssertEqual(dps!, 30_000 / (pace * cadence), accuracy: 0.0001)
    }

    func testDistancePerStrokeBikeUses1000mBasis() {
        let pace: TimeInterval = 120
        let cadence: Double = 80
        let dps = ReplayInspector.distancePerStroke(sport: .bike, pace: pace, cadence: cadence)
        XCTAssertNotNil(dps)
        // 60000 / (pace * cadence) = 60000 / (120 * 80) = 60000 / 9600 = 6.25
        XCTAssertEqual(dps!, 60_000 / (pace * cadence), accuracy: 0.0001)
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
