import XCTest
@testable import RowPlayCore

final class WorkoutQueryTests: XCTestCase {
    // MARK: - Fixtures

    private func makeWorkout(
        id: Int,
        sport: Sport = .rower,
        distance: Double = 2_000,
        time: TimeInterval = 480,
        pace: TimeInterval = 120,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        workoutType: String = "JustRow",
        comments: String? = nil,
        source: String? = nil,
        hasStrokeData: Bool = true,
        wattMinutes: Double? = nil
    ) -> Workout {
        Workout(
            id: id,
            date: date,
            sport: sport,
            distance: distance,
            time: time,
            pace: pace,
            wattMinutes: wattMinutes,
            workoutType: workoutType,
            comments: comments,
            source: source,
            hasStrokeData: hasStrokeData
        )
    }

    private func makeDate(_ daysSinceEpoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(daysSinceEpoch * 86_400))
    }

    // MARK: - Filter Tests

    func testFilterBySport() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower),
            makeWorkout(id: 2, sport: .skierg),
            makeWorkout(id: 3, sport: .bike),
        ]
        let q = WorkoutListQuery(sport: .skierg)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2])
    }

    func testFilterByWorkoutType() {
        let workouts = [
            makeWorkout(id: 1, workoutType: "2000m test"),
            makeWorkout(id: 2, workoutType: "JustRow"),
        ]
        let q = WorkoutListQuery(workoutType: "2000m test")
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFilterBySearchTextMatchesSourceCaseInsensitively() {
        let workouts = [
            makeWorkout(id: 1, source: "Concept2 Online Logbook"),
            makeWorkout(id: 2, source: "Manual entry"),
        ]
        let q = WorkoutListQuery(searchText: "logbook")
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFilterBySearchText() {
        let workouts = [
            makeWorkout(id: 1, workoutType: "2000m test", comments: "PB attempt"),
            makeWorkout(id: 2, workoutType: "JustRow", comments: "easy session"),
        ]
        let q = WorkoutListQuery(searchText: "pb")
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFilterByDistanceChip() {
        let workouts = [
            makeWorkout(id: 1, distance: 2_003), // within ±2%
            makeWorkout(id: 2, distance: 1_900), // outside ±2%
            makeWorkout(id: 3, distance: 1_998), // within ±2%
        ]
        let q = WorkoutListQuery(distanceM: 2_000)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id).sorted(), [1, 3])
    }

    func testFilterByDurationChip() {
        let workouts = [
            makeWorkout(id: 1, time: 1_200), // exactly 20 min
            makeWorkout(id: 2, time: 1_800), // 30 min
            makeWorkout(id: 3, time: 900),   // 15 min — outside ±10% of 1200
        ]
        let q = WorkoutListQuery(durationMin: 1_080, durationMax: 1_320) // 20 min ±10%
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFilterByDateRange() {
        let workouts = [
            makeWorkout(id: 1, date: makeDate(1)),
            makeWorkout(id: 2, date: makeDate(2)),
            makeWorkout(id: 3, date: makeDate(3)),
            makeWorkout(id: 4, date: makeDate(4)),
        ]
        let q = WorkoutListQuery(dateFrom: "1970-01-03", dateTo: "1970-01-04")
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id).sorted(), [2, 3])
    }

    func testFilterByHasStroke() {
        let workouts = [
            makeWorkout(id: 1, hasStrokeData: true),
            makeWorkout(id: 2, hasStrokeData: false),
        ]
        let qTrue = WorkoutListQuery(hasStroke: true)
        XCTAssertEqual(WorkoutQuery.filterAndSortWorkouts(workouts, query: qTrue).map(\.id), [1])

        let qFalse = WorkoutListQuery(hasStroke: false)
        XCTAssertEqual(WorkoutQuery.filterAndSortWorkouts(workouts, query: qFalse).map(\.id), [2])
    }

    func testFilterByPBsOnly() {
        let workouts = [
            makeWorkout(id: 1, distance: 2_000, time: 400),
            makeWorkout(id: 2, distance: 2_000, time: 420),
        ]
        let q = WorkoutListQuery(pbsOnly: true)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testFilterByPBsOnlyRespectsSportFilter() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2_000, time: 400),
            makeWorkout(id: 2, sport: .skierg, distance: 2_000, time: 430),
            makeWorkout(id: 3, sport: .skierg, distance: 2_000, time: 460),
        ]
        let q = WorkoutListQuery(sport: .skierg, pbsOnly: true)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2])
    }

    // MARK: - Sort Tests

    func testSortByDateDescending() {
        let workouts = [
            makeWorkout(id: 1, date: makeDate(100)),
            makeWorkout(id: 2, date: makeDate(200)),
        ]
        let q = WorkoutListQuery(sort: .date, dir: .desc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByDateAscending() {
        let workouts = [
            makeWorkout(id: 1, date: makeDate(200)),
            makeWorkout(id: 2, date: makeDate(100)),
        ]
        let q = WorkoutListQuery(sort: .date, dir: .asc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByDistance() {
        let workouts = [
            makeWorkout(id: 1, distance: 5_000),
            makeWorkout(id: 2, distance: 2_000),
        ]
        let q = WorkoutListQuery(sort: .distance, dir: .asc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByDistanceDescending() {
        let workouts = [
            makeWorkout(id: 1, distance: 2_000),
            makeWorkout(id: 2, distance: 5_000),
        ]
        let q = WorkoutListQuery(sort: .distance, dir: .desc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByTime() {
        let workouts = [
            makeWorkout(id: 1, time: 600),
            makeWorkout(id: 2, time: 400),
        ]
        let q = WorkoutListQuery(sort: .time, dir: .asc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByTimeDescending() {
        let workouts = [
            makeWorkout(id: 1, time: 400),
            makeWorkout(id: 2, time: 600),
        ]
        let q = WorkoutListQuery(sort: .time, dir: .desc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByPace() {
        let workouts = [
            makeWorkout(id: 1, pace: 130),
            makeWorkout(id: 2, pace: 110),
        ]
        let q = WorkoutListQuery(sort: .pace, dir: .asc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByPaceDescending() {
        let workouts = [
            makeWorkout(id: 1, pace: 110),
            makeWorkout(id: 2, pace: 130),
        ]
        let q = WorkoutListQuery(sort: .pace, dir: .desc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByPower() {
        let workouts = [
            makeWorkout(id: 1, time: 400, wattMinutes: 100), // watts = 100*60/400 = 15
            makeWorkout(id: 2, time: 400, wattMinutes: 200), // watts = 200*60/400 = 30
        ]
        let q = WorkoutListQuery(sort: .power, dir: .desc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testSortByPowerAscending() {
        let workouts = [
            makeWorkout(id: 1, time: 400, wattMinutes: 200), // watts = 30
            makeWorkout(id: 2, time: 400, wattMinutes: 100), // watts = 15
        ]
        let q = WorkoutListQuery(sort: .power, dir: .asc)
        let result = WorkoutQuery.filterAndSortWorkouts(workouts, query: q)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    // MARK: - Chip Toggle Tests

    func testToggleDistanceChipOn() {
        let q = WorkoutQuery.toggleDistanceChip(WorkoutQuery.defaultQuery, metres: 2_000)
        XCTAssertEqual(q.distanceM, 2_000)
        XCTAssertNil(q.durationMin)
        XCTAssertNil(q.durationMax)
    }

    func testToggleDistanceChipOff() {
        var q = WorkoutQuery.defaultQuery
        q.distanceM = 2_000
        let toggled = WorkoutQuery.toggleDistanceChip(q, metres: 2_000)
        XCTAssertNil(toggled.distanceM)
    }

    func testToggleDurationChipOn() {
        let q = WorkoutQuery.toggleDurationChip(WorkoutQuery.defaultQuery, seconds: 1_800)
        XCTAssertEqual(q.durationMin, 1_620)
        XCTAssertEqual(q.durationMax, 1_980)
        XCTAssertNil(q.distanceM)
    }

    func testToggleDurationChipOff() {
        var q = WorkoutQuery.defaultQuery
        q.durationMin = 1_620
        q.durationMax = 1_980
        let toggled = WorkoutQuery.toggleDurationChip(q, seconds: 1_800)
        XCTAssertNil(toggled.durationMin)
        XCTAssertNil(toggled.durationMax)
    }

    func testDurationChipActive() {
        var q = WorkoutQuery.defaultQuery
        q.durationMin = 1_620
        q.durationMax = 1_980
        XCTAssertTrue(WorkoutQuery.durationChipActive(q, seconds: 1_800))
        XCTAssertFalse(WorkoutQuery.durationChipActive(q, seconds: 3_600))
    }

    // MARK: - avgPowerWatts Tests

    func testAvgPowerWatts() {
        let w = makeWorkout(id: 1, time: 400, wattMinutes: 200)
        let watts = WorkoutQuery.avgPowerWatts(for: w)
        XCTAssertEqual(watts ?? 0, 30.0, accuracy: 0.01) // 200*60/400 = 30
    }

    func testAvgPowerWattsNilWhenNoWattMinutes() {
        let w = makeWorkout(id: 1, time: 400, wattMinutes: nil)
        XCTAssertNil(WorkoutQuery.avgPowerWatts(for: w))
    }

    func testAvgPowerWattsNilWhenZeroTime() {
        let w = makeWorkout(id: 1, time: 0, wattMinutes: 100)
        XCTAssertNil(WorkoutQuery.avgPowerWatts(for: w))
    }

    // MARK: - pbWorkoutIds Tests

    func testPbWorkoutIdsFindsBestPerDistance() {
        let workouts = [
            makeWorkout(id: 1, distance: 2_000, time: 400),
            makeWorkout(id: 2, distance: 2_005, time: 420), // within ±2%, slower
            makeWorkout(id: 3, distance: 5_000, time: 1_100),
            makeWorkout(id: 4, distance: 4_980, time: 1_050), // within ±2%, faster
        ]
        let pbs = WorkoutQuery.pbWorkoutIds(workouts: workouts)
        XCTAssertTrue(pbs.contains(1)) // best 2k
        XCTAssertTrue(pbs.contains(4)) // best 5k
        XCTAssertFalse(pbs.contains(2))
        XCTAssertFalse(pbs.contains(3))
    }

    func testPbWorkoutIdsBySport() {
        let workouts = [
            makeWorkout(id: 1, sport: .rower, distance: 2_000, time: 400),
            makeWorkout(id: 2, sport: .skierg, distance: 2_000, time: 500),
        ]
        let rowerPBs = WorkoutQuery.pbWorkoutIds(workouts: workouts, sport: .rower)
        XCTAssertTrue(rowerPBs.contains(1))
        XCTAssertFalse(rowerPBs.contains(2))
    }

    // MARK: - Empty / Edge Cases

    func testEmptyWorkoutsReturnEmpty() {
        let q = WorkoutQuery.defaultQuery
        let result = WorkoutQuery.filterAndSortWorkouts([], query: q)
        XCTAssertTrue(result.isEmpty)
    }

    func testIsFilteredDetectsActiveFilters() {
        XCTAssertFalse(WorkoutQuery.defaultQuery.isFiltered)

        var q = WorkoutQuery.defaultQuery
        q.sport = .rower
        XCTAssertTrue(q.isFiltered)

        q = WorkoutQuery.defaultQuery
        q.searchText = "test"
        XCTAssertTrue(q.isFiltered)

        q = WorkoutQuery.defaultQuery
        q.pbsOnly = true
        XCTAssertTrue(q.isFiltered)
    }

    func testClearFiltersPreservesSort() {
        var q = WorkoutQuery.defaultQuery
        q.sport = .rower
        q.pbsOnly = true
        q.sort = .pace
        q.dir = .asc

        let cleared = WorkoutQuery.clearFilters(q)
        XCTAssertNil(cleared.sport)
        XCTAssertFalse(cleared.pbsOnly)
        XCTAssertEqual(cleared.sort, .pace)
        XCTAssertEqual(cleared.dir, .asc)
    }

    func testDefaultQuerySortsByDateDescending() {
        let q = WorkoutQuery.defaultQuery
        XCTAssertEqual(q.sort, .date)
        XCTAssertEqual(q.dir, .desc)
    }
}
