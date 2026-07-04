import XCTest
@testable import RowPlayCore

final class HrImportTests: XCTestCase {

    private func makeStroke(t: Double, d: Double, hr: Int? = nil) -> Stroke {
        Stroke(t: t, d: d, pace: 120, cadence: 28, heartRate: hr, watts: 200)
    }

    // MARK: - Extract HR Series

    func testExtractHrSeriesFiltersInvalid() {
        let strokes = [
            makeStroke(t: 0, d: 0, hr: 150),
            makeStroke(t: 2, d: 10, hr: nil),    // no HR
            makeStroke(t: 4, d: 20, hr: 0),      // zero HR
            makeStroke(t: 6, d: 30, hr: 160),
        ]
        let samples = HrImport.extractHrSeries(strokes)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].hr, 150)
        XCTAssertEqual(samples[1].hr, 160)
    }

    func testExtractHrSeriesSortedByTime() {
        let strokes = [
            makeStroke(t: 10, d: 50, hr: 160),
            makeStroke(t: 0, d: 0, hr: 150),
            makeStroke(t: 5, d: 25, hr: 155),
        ]
        let samples = HrImport.extractHrSeries(strokes)
        XCTAssertEqual(samples[0].t, 0)
        XCTAssertEqual(samples[1].t, 5)
        XCTAssertEqual(samples[2].t, 10)
    }

    // MARK: - Interpolate HR

    func testInterpolateHrExactMatch() {
        let samples = [HrSample(t: 0, hr: 100), HrSample(t: 10, hr: 150)]
        XCTAssertEqual(HrImport.interpolateHr(samples, at: 0), 100)
        XCTAssertEqual(HrImport.interpolateHr(samples, at: 10), 150)
    }

    func testInterpolateHrMidpoint() {
        let samples = [HrSample(t: 0, hr: 100), HrSample(t: 10, hr: 150)]
        XCTAssertEqual(HrImport.interpolateHr(samples, at: 5), 125)
    }

    func testInterpolateHrOutsideRange() {
        let samples = [HrSample(t: 5, hr: 100), HrSample(t: 10, hr: 150)]
        XCTAssertNil(HrImport.interpolateHr(samples, at: 0))
        XCTAssertNil(HrImport.interpolateHr(samples, at: 15))
    }

    func testInterpolateHrEmptySamples() {
        XCTAssertNil(HrImport.interpolateHr([], at: 5))
    }

    // MARK: - Merge HR Into Strokes

    func testMergeHrIntoStrokes() {
        let strokes = [
            makeStroke(t: 0, d: 0),
            makeStroke(t: 5, d: 25),
            makeStroke(t: 10, d: 50),
        ]
        let samples = [HrSample(t: 0, hr: 100), HrSample(t: 10, hr: 160)]
        let merged = HrImport.mergeHrIntoStrokes(strokes, samples: samples, offsetSec: 0)
        XCTAssertEqual(merged[0].heartRate, 100)
        XCTAssertEqual(merged[1].heartRate, 130) // midpoint
        XCTAssertEqual(merged[2].heartRate, 160)
    }

    func testMergeHrIntoStrokesWithOffset() {
        let strokes = [makeStroke(t: 0, d: 0)]
        let samples = [HrSample(t: 5, hr: 140)]
        let merged = HrImport.mergeHrIntoStrokes(strokes, samples: samples, offsetSec: 5)
        XCTAssertEqual(merged[0].heartRate, 140) // t=0 + offset=5 → samples at t=5
    }

    // MARK: - Summarize HR

    func testSummarizeHr() {
        let strokes = [
            makeStroke(t: 0, d: 0, hr: 100),
            makeStroke(t: 2, d: 10, hr: 150),
            makeStroke(t: 4, d: 20, hr: 120),
        ]
        let stats = HrImport.summarizeHr(strokes)
        XCTAssertEqual(stats.avg, 123)
        XCTAssertEqual(stats.min, 100)
        XCTAssertEqual(stats.max, 150)
    }

    func testSummarizeHrRoundsAverageLikeWeb() {
        let strokes = [
            makeStroke(t: 0, d: 0, hr: 100),
            makeStroke(t: 2, d: 10, hr: 101),
        ]
        let stats = HrImport.summarizeHr(strokes)
        XCTAssertEqual(stats.avg, 101)
    }

    func testSummarizeHrNoData() {
        let strokes = [makeStroke(t: 0, d: 0, hr: nil)]
        let stats = HrImport.summarizeHr(strokes)
        XCTAssertNil(stats.avg)
        XCTAssertNil(stats.min)
        XCTAssertNil(stats.max)
    }

    // MARK: - Strokes Have HR

    func testStrokesHaveHrTrue() {
        let strokes = [makeStroke(t: 0, d: 0, hr: 150)]
        XCTAssertTrue(HrImport.strokesHaveHr(strokes))
    }

    func testStrokesHaveHrFalse() {
        let strokes = [makeStroke(t: 0, d: 0, hr: nil)]
        XCTAssertFalse(HrImport.strokesHaveHr(strokes))
    }

    // MARK: - Apply HR Import

    func testApplyHrImportUpdatesWorkoutDetail() {
        let workout = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 1_000_000),
            sport: .rower,
            distance: 100,
            time: 30,
            pace: 150,
            workoutType: "fixed_distance",
            hasStrokeData: true
        )
        let strokes = [
            makeStroke(t: 0, d: 0),
            makeStroke(t: 5, d: 25),
            makeStroke(t: 10, d: 50),
            makeStroke(t: 15, d: 75),
            makeStroke(t: 20, d: 100),
        ]
        let splits = [
            Split(index: 0, distance: 50, time: 15, pace: 150),
            Split(index: 1, distance: 50, time: 15, pace: 150),
        ]
        let detail = WorkoutDetail(workout: workout, strokes: strokes, splits: splits)

        let samples = [HrSample(t: 0, hr: 100), HrSample(t: 20, hr: 160)]
        let result = HrImport.applyHrImport(detail, samples: samples, offsetSec: 0)

        XCTAssertNotNil(result.workout.heartRateAvg)
        // All strokes should have HR now
        XCTAssertTrue(result.strokes.allSatisfy { $0.heartRate != nil && $0.heartRate! > 0 })
    }

    func testApplyHrImportRoundsSplitAverageLikeWeb() {
        let workout = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 1_000_000),
            sport: .rower,
            distance: 20,
            time: 4,
            pace: 100,
            workoutType: "fixed_distance",
            hasStrokeData: true
        )
        let strokes = [
            makeStroke(t: 0, d: 0),
            makeStroke(t: 2, d: 10),
            makeStroke(t: 4, d: 20),
        ]
        let splits = [
            Split(index: 0, distance: 20, time: 4, pace: 100),
        ]
        let detail = WorkoutDetail(workout: workout, strokes: strokes, splits: splits)

        let samples = [HrSample(t: 0, hr: 100), HrSample(t: 4, hr: 101)]
        let result = HrImport.applyHrImport(detail, samples: samples, offsetSec: 0)

        XCTAssertEqual(result.workout.heartRateAvg, 101)
        XCTAssertEqual(result.splits[0].heartRate?.average, 101)
    }
}
