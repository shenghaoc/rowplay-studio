import XCTest
@testable import RowPlayCore

final class RepDetectionTests: XCTestCase {

    private func makeStroke(t: Double, d: Double, pace: Double = 120, spm: Double = 28, hr: Int? = nil) -> Stroke {
        Stroke(t: t, d: d, pace: pace, cadence: spm, heartRate: hr, watts: 200)
    }

    private func makeDetail(splits: [Split], strokes: [Stroke] = []) -> WorkoutDetail {
        let workout = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 1_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "fixed_distance",
            hasStrokeData: true,
            isInterval: true
        )
        return WorkoutDetail(workout: workout, strokes: strokes, splits: splits)
    }

    // MARK: - Detect Reps

    func testDetectRepsWithTwoWorkIntervals() {
        let splits = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
            Split(index: 1, distance: 500, time: 125, pace: 125),
        ]
        let detail = makeDetail(splits: splits)
        let reps = RepDetection.detectReps(detail)
        XCTAssertNotNil(reps)
        XCTAssertEqual(reps!.count, 2)
        XCTAssertEqual(reps![0].repIndex, 0)
        XCTAssertEqual(reps![1].repIndex, 1)
    }

    func testDetectRepsWithShortSplitsReturnsNil() {
        let splits = [
            Split(index: 0, distance: 100, time: 20, pace: 100), // < 30s
            Split(index: 1, distance: 100, time: 25, pace: 100), // < 30s
        ]
        let detail = makeDetail(splits: splits)
        XCTAssertNil(RepDetection.detectReps(detail))
    }

    func testDetectRepsWithSingleWorkSplitReturnsNil() {
        let splits = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
        ]
        let detail = makeDetail(splits: splits)
        XCTAssertNil(RepDetection.detectReps(detail))
    }

    func testDetectRepsWithMixedSplits() {
        // All splits >= 30s are treated as work reps (native Split has no isRest field)
        let splits = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
            Split(index: 1, distance: 100, time: 60, pace: 300),  // slow/rest-like, but >= 30s
            Split(index: 2, distance: 500, time: 125, pace: 125),
        ]
        let detail = makeDetail(splits: splits)
        let reps = RepDetection.detectReps(detail)
        XCTAssertNotNil(reps)
        XCTAssertEqual(reps!.count, 3) // all three >= 30s
    }

    // MARK: - Rep Avg Pace

    func testRepAvgPace() {
        let series = RepSeries(
            repIndex: 0, avgPace: 118.5,
            times: [0, 1, 2], pace: [118, 119, 118.5],
            rate: [28, 28, 28], power: [200, 200, 200], hr: [0, 0, 0]
        )
        XCTAssertEqual(RepDetection.repAvgPace(series), 118.5)
    }

    // MARK: - Reps Have HR

    func testRepsHaveHrTrue() {
        let reps = [
            RepSeries(repIndex: 0, avgPace: 120, times: [], pace: [], rate: [], power: [], hr: [0, 0]),
            RepSeries(repIndex: 1, avgPace: 120, times: [], pace: [], rate: [], power: [], hr: [150, 155]),
        ]
        XCTAssertTrue(RepDetection.repsHaveHr(reps))
    }

    func testRepsHaveHrFalse() {
        let reps = [
            RepSeries(repIndex: 0, avgPace: 120, times: [], pace: [], rate: [], power: [], hr: [0, 0]),
            RepSeries(repIndex: 1, avgPace: 120, times: [], pace: [], rate: [], power: [], hr: [0, 0]),
        ]
        XCTAssertFalse(RepDetection.repsHaveHr(reps))
    }

    // MARK: - With Strokes

    func testDetectRepsUsesStrokesWhenAvailable() {
        let splits = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
            Split(index: 1, distance: 500, time: 120, pace: 120),
        ]
        // 60 strokes total: 30 per rep
        let strokes = (0..<60).map { i in
            makeStroke(t: Double(i) * 2, d: Double(i) * (1000.0 / 60.0))
        }
        let detail = makeDetail(splits: splits, strokes: strokes)
        let reps = RepDetection.detectReps(detail)
        XCTAssertNotNil(reps)
        XCTAssertEqual(reps!.count, 2)
        // First rep should have strokes with times relative to t=0
        XCTAssertEqual(reps![0].times.first ?? -1, 0, accuracy: 0.01)
    }
}
