import XCTest
@testable import RowPlayCore

final class WorkoutComparisonTests: XCTestCase {

    // MARK: - Fixtures

    private func makeWorkout(
        id: Int = 1,
        sport: Sport = .rower,
        distance: Double = 2000,
        time: TimeInterval = 480,
        pace: TimeInterval = 120,
        workoutType: String = "fixed_distance",
        isInterval: Bool = false
    ) -> Workout {
        Workout(
            id: id,
            date: Date(timeIntervalSince1970: 1_000_000),
            sport: sport,
            distance: distance,
            time: time,
            pace: pace,
            workoutType: workoutType,
            hasStrokeData: true,
            isInterval: isInterval
        )
    }

    private func makeStroke(t: Double, d: Double, pace: Double = 120, spm: Double = 28, hr: Int? = nil, watts: Int = 200) -> Stroke {
        Stroke(t: t, d: d, pace: pace, cadence: spm, heartRate: hr, watts: watts)
    }

    private func makeDetail(
        workout: Workout,
        strokes: [Stroke] = [],
        splits: [Split] = []
    ) -> WorkoutDetail {
        WorkoutDetail(workout: workout, strokes: strokes, splits: splits)
    }

    // MARK: - Compare Verdict

    func testCompareVerdictLikeForLikeAAster() {
        let a = makeDetail(workout: makeWorkout(distance: 2000, time: 470, pace: 117.5))
        let b = makeDetail(workout: makeWorkout(id: 2, distance: 2000, time: 480, pace: 120))
        let verdict = WorkoutComparison.compareVerdict(a, b)
        XCTAssertEqual(verdict.winner, .a)
        XCTAssertEqual(verdict.timeDeltaSec ?? 0, 10, accuracy: 0.01)
    }

    func testCompareVerdictLikeForLikeBFaster() {
        let a = makeDetail(workout: makeWorkout(distance: 2000, time: 490, pace: 122.5))
        let b = makeDetail(workout: makeWorkout(id: 2, distance: 2000, time: 480, pace: 120))
        let verdict = WorkoutComparison.compareVerdict(a, b)
        XCTAssertEqual(verdict.winner, .b)
    }

    func testCompareVerdictTie() {
        let a = makeDetail(workout: makeWorkout(distance: 2000, time: 480, pace: 120))
        let b = makeDetail(workout: makeWorkout(id: 2, distance: 2000, time: 480, pace: 120))
        let verdict = WorkoutComparison.compareVerdict(a, b)
        XCTAssertEqual(verdict.winner, .tie)
    }

    func testCompareVerdictCrossSport() {
        let a = makeDetail(workout: makeWorkout(sport: .rower, distance: 2000, time: 480))
        let b = makeDetail(workout: makeWorkout(id: 2, sport: .bike, distance: 2000, time: 480))
        let verdict = WorkoutComparison.compareVerdict(a, b)
        XCTAssertEqual(verdict.winner, .tie)
    }

    func testCompareVerdictDifferentDistancesComparesPace() {
        // 2k vs 5k — different distance bands, falls through to pace comparison
        let a = makeDetail(workout: makeWorkout(distance: 2000, time: 480, pace: 118))
        let b = makeDetail(workout: makeWorkout(id: 2, distance: 5000, time: 1200, pace: 120))
        let verdict = WorkoutComparison.compareVerdict(a, b)
        XCTAssertEqual(verdict.winner, .a) // A has lower pace
        XCTAssertNil(verdict.timeDeltaSec)
    }

    // MARK: - Side Stats

    func testSideStatsBasic() {
        var strokes: [Stroke] = []
        for i in 0..<100 {
            strokes.append(makeStroke(t: Double(i) * 2, d: Double(i) * 10, pace: 120 + Double(i % 5), watts: 200 + i % 10))
        }
        let workout = makeWorkout(distance: 1000, time: 200, pace: 100)
        let detail = makeDetail(workout: workout, strokes: strokes)
        let stats = WorkoutComparison.sideStats(detail)

        XCTAssertEqual(stats.time, 200)
        XCTAssertEqual(stats.pace, 100)
        XCTAssertGreaterThan(stats.avgDps, 0)
    }

    func testSideStatsWithWattMinutes() {
        // wattMinutes = avgWatts * time / 60
        let workout = makeWorkout(distance: 2000, time: 480, pace: 120)
        var w = workout
        w.wattMinutes = 200 * 480 / 60  // 200W average
        let detail = makeDetail(workout: w)
        let stats = WorkoutComparison.sideStats(detail)
        XCTAssertEqual(stats.avgWatts, 200)
    }

    func testSideStatsUsesSportAwareWattsFallback() {
        let workout = makeWorkout(sport: .bike, distance: 2000, time: 480, pace: 100)
        let detail = makeDetail(workout: workout)
        let stats = WorkoutComparison.sideStats(detail)
        XCTAssertEqual(stats.avgWatts, 44)
    }

    func testSideStatsComputesDpsFromPaceAndCadence() {
        let strokes = [
            makeStroke(t: 0, d: 10, pace: 120, spm: 30),
            makeStroke(t: 2, d: 25, pace: 150, spm: 20),
        ]
        let detail = makeDetail(workout: makeWorkout(), strokes: strokes)
        let stats = WorkoutComparison.sideStats(detail)
        let expected = (30_000 / (120.0 * 30.0) + 30_000 / (150.0 * 20.0)) / 2
        XCTAssertEqual(stats.avgDps, expected, accuracy: 0.001)
    }

    func testSideStatsRoundsComputedHeartRateAverage() {
        let strokes = [
            makeStroke(t: 0, d: 0, hr: 100),
            makeStroke(t: 2, d: 20, hr: 101),
        ]
        let detail = makeDetail(workout: makeWorkout(), strokes: strokes)
        let stats = WorkoutComparison.sideStats(detail)
        XCTAssertEqual(stats.avgHr, 101)
    }

    func testSideStatsBest5sPowerUsesTimeWeightedWindow() {
        let strokes = [
            makeStroke(t: 0, d: 0, watts: 100),
            makeStroke(t: 1, d: 10, watts: 100),
            makeStroke(t: 5, d: 50, watts: 300),
            makeStroke(t: 6, d: 60, watts: 300),
        ]
        let detail = makeDetail(workout: makeWorkout(), strokes: strokes)
        let stats = WorkoutComparison.sideStats(detail)
        XCTAssertEqual(stats.best5sPower, 220)
    }

    // MARK: - Interval Compare

    func testCompareIntervalRepsBothInterval() {
        let splitsA = [
            Split(index: 0, distance: 500, time: 120, pace: 120),
            Split(index: 1, distance: 500, time: 125, pace: 125),
        ]
        let splitsB = [
            Split(index: 0, distance: 500, time: 118, pace: 118),
            Split(index: 1, distance: 500, time: 122, pace: 122),
        ]
        let workoutA = makeWorkout(distance: 1000, time: 245, pace: 122.5, isInterval: true)
        let workoutB = makeWorkout(id: 2, distance: 1000, time: 240, pace: 120, isInterval: true)
        let a = makeDetail(workout: workoutA, splits: splitsA)
        let b = makeDetail(workout: workoutB, splits: splitsB)

        let rows = WorkoutComparison.compareIntervalReps(a, b)
        XCTAssertNotNil(rows)
        XCTAssertEqual(rows!.count, 2)
        XCTAssertEqual(rows![0].index, 1)
        XCTAssertEqual(rows![0].paceDelta, 2, accuracy: 0.01)
    }

    func testCompareIntervalRepsNotInterval() {
        let workoutA = makeWorkout(isInterval: false)
        let workoutB = makeWorkout(id: 2, isInterval: false)
        let a = makeDetail(workout: workoutA)
        let b = makeDetail(workout: workoutB)
        XCTAssertNil(WorkoutComparison.compareIntervalReps(a, b))
    }

    func testCompareIntervalRepsDifferentSport() {
        let workoutA = makeWorkout(sport: .rower, isInterval: true)
        let workoutB = makeWorkout(id: 2, sport: .bike, isInterval: true)
        let splits = [Split(index: 0, distance: 500, time: 120, pace: 120), Split(index: 1, distance: 500, time: 120, pace: 120)]
        let a = makeDetail(workout: workoutA, splits: splits)
        let b = makeDetail(workout: workoutB, splits: splits)
        XCTAssertNil(WorkoutComparison.compareIntervalReps(a, b))
    }

    // MARK: - Distance Overlay

    func testBuildDistanceOverlay() {
        var strokesA: [Stroke] = []
        var strokesB: [Stroke] = []
        for i in 0..<20 {
            strokesA.append(makeStroke(t: Double(i) * 2, d: Double(i) * 50))
            strokesB.append(makeStroke(t: Double(i) * 2.5, d: Double(i) * 40))
        }
        let overlay = WorkoutComparison.buildDistanceOverlay(strokesA, strokesB)
        XCTAssertNotNil(overlay)
        XCTAssertEqual(overlay!.alignedMetres, 760, accuracy: 1) // min(950, 760)
        XCTAssertEqual(overlay!.xs.count, 121) // steps=120 → 121 points
    }

    func testBuildDistanceOverlayEmpty() {
        XCTAssertNil(WorkoutComparison.buildDistanceOverlay([], []))
    }
}
