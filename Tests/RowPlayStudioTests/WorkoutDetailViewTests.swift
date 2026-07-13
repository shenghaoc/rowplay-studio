import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class WorkoutDetailViewTests: XCTestCase {
    func testDownsampleStrokesCapsCountAndPreservesEndpoints() {
        let strokes = makeStrokes(count: 999)

        let sampled = WorkoutStrokeAnalysisView.downsampleStrokes(strokes, limit: 500)

        XCTAssertEqual(sampled.count, 500)
        XCTAssertEqual(sampled.first, strokes.first)
        XCTAssertEqual(sampled.last, strokes.last)
        XCTAssertTrue(zip(sampled, sampled.dropFirst()).allSatisfy { $0.t < $1.t })
    }

    func testDownsampleStrokesLeavesBoundedInputUnchanged() {
        let strokes = makeStrokes(count: 12)

        XCTAssertEqual(WorkoutStrokeAnalysisView.downsampleStrokes(strokes, limit: 500), strokes)
    }

    func testSplitBoundaryDistancesFollowDistanceTransform() {
        let splits = [
            Split(index: 1, distance: 1_000, time: 240, pace: 120),
            Split(index: 2, distance: 1_000, time: 240, pace: 120)
        ]

        let kilometres = WorkoutStrokeAnalysisView.computeSplitBoundaryDistances(
            splits: splits,
            distanceTransform: { $0 / 1_000 }
        )
        let miles = WorkoutStrokeAnalysisView.computeSplitBoundaryDistances(
            splits: splits,
            distanceTransform: { $0 / 1_609.344 }
        )

        XCTAssertEqual(kilometres, [1])
        XCTAssertEqual(miles[0], 0.621371, accuracy: 0.000001)
    }

    func testPowerTextRejectsInvalidPace() {
        XCTAssertEqual(WorkoutDetailView.powerText(for: .rower, pace: 0), "-")
        XCTAssertEqual(WorkoutDetailView.powerText(for: .rower, pace: -.infinity), "-")
        XCTAssertEqual(WorkoutDetailView.powerText(for: .rower, pace: .nan), "-")
    }

    func testPowerTextFormatsValidPace() {
        XCTAssertEqual(WorkoutDetailView.powerText(for: .rower, pace: 120), "203")
        XCTAssertEqual(WorkoutDetailView.powerText(for: .bike, pace: 120), "25")
    }

    func testPowerTextRejectsUnrealisticDerivedPower() {
        XCTAssertEqual(WorkoutDetailView.powerText(for: .rower, pace: 1), "-")
    }

    private func makeStrokes(count: Int) -> [Stroke] {
        (0..<count).map { index in
            Stroke(
                t: TimeInterval(index),
                d: Double(index) * 10,
                pace: 120 + Double(index % 5),
                cadence: 28,
                watts: 200 + index % 25
            )
        }
    }
}
