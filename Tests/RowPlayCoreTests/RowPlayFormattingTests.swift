import XCTest
@testable import RowPlayCore

final class RowPlayFormattingTests: XCTestCase {

    // MARK: - time()

    func testTimeZero() {
        XCTAssertEqual(RowPlayFormatting.time(0), "0:00")
    }

    func testTimeSecondsOnly() {
        XCTAssertEqual(RowPlayFormatting.time(45), "0:45")
    }

    func testTimeMinutesAndSeconds() {
        XCTAssertEqual(RowPlayFormatting.time(125), "2:05")
    }

    func testTimeHours() {
        XCTAssertEqual(RowPlayFormatting.time(3661), "1:01:01")
    }

    func testTimeTenths() {
        XCTAssertEqual(RowPlayFormatting.time(65.3, tenths: true), "1:05.3")
    }

    func testTimeTenthsZero() {
        XCTAssertEqual(RowPlayFormatting.time(0, tenths: true), "0:00.0")
    }

    func testTimeNegativeReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.time(-1), "--:--")
    }

    func testTimeInfiniteReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.time(.infinity), "--:--")
    }

    func testTimeNaNReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.time(.nan), "--:--")
    }

    func testTimeUnrepresentableFiniteValueReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.time(.greatestFiniteMagnitude), "--:--")
    }

    // MARK: - pace()

    func testPaceNormal() {
        XCTAssertEqual(RowPlayFormatting.pace(120), "2:00.0/500m")
    }

    func testPaceSlow() {
        XCTAssertEqual(RowPlayFormatting.pace(300), "5:00.0/500m")
    }

    func testPaceZeroReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.pace(0), "--:--")
    }

    func testPaceNegativeReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.pace(-1), "--:--")
    }

    func testPaceInfiniteReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.pace(.infinity), "--:--")
    }

    // MARK: - distance()

    func testDistanceMetres() {
        XCTAssertEqual(RowPlayFormatting.distance(500), "500 m")
    }

    func testDistanceKilometres() {
        XCTAssertEqual(RowPlayFormatting.distance(5000), "5.00 km")
    }

    func testDistanceNegativeKilometresUsesAbsoluteThreshold() {
        XCTAssertEqual(RowPlayFormatting.distance(-1_500), "-1.50 km")
    }

    func testDistanceExactlyOneKm() {
        XCTAssertEqual(RowPlayFormatting.distance(1000), "1.00 km")
    }

    func testDistanceZero() {
        XCTAssertEqual(RowPlayFormatting.distance(0), "0 m")
    }

    func testDistanceInfiniteReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.distance(.infinity), "--")
    }

    func testDistanceNaNReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.distance(.nan), "--")
    }

    // MARK: - distance() imperial

    func testDistanceImperialFeet() {
        // 100 m ≈ 328 ft
        XCTAssertEqual(RowPlayFormatting.distance(100, unit: .imperial), "328 ft")
    }

    func testDistanceImperialMiles() {
        // 1609.344 m = 1 mile
        XCTAssertEqual(RowPlayFormatting.distance(1_609.344, unit: .imperial), "1.00 mi")
    }

    func testDistanceImperialNegativeMilesUsesAbsoluteThreshold() {
        XCTAssertEqual(RowPlayFormatting.distance(-500, unit: .imperial), "-0.31 mi")
    }

    func testDistanceImperialThreshold() {
        // 304.8 m = 1000 ft → switches to miles
        XCTAssertEqual(RowPlayFormatting.distance(304.8, unit: .imperial), "0.19 mi")
    }

    func testDistanceImperialBelowThreshold() {
        // 304 m < 304.8 → still feet
        XCTAssertEqual(RowPlayFormatting.distance(304, unit: .imperial), "997 ft")
    }

    func testDistanceImperial5k() {
        // 5000 m ≈ 3.11 mi
        let result = RowPlayFormatting.distance(5_000, unit: .imperial)
        XCTAssertTrue(result.hasSuffix("mi"))
        XCTAssertTrue(result.hasPrefix("3."))
    }

    func testDistanceImperialZero() {
        XCTAssertEqual(RowPlayFormatting.distance(0, unit: .imperial), "0 ft")
    }

    func testDistanceImperialInfinite() {
        XCTAssertEqual(RowPlayFormatting.distance(.infinity, unit: .imperial), "--")
    }

    func testDistanceImperialNaN() {
        XCTAssertEqual(RowPlayFormatting.distance(.nan, unit: .imperial), "--")
    }

    // MARK: - distance() default unit is metric

    func testDistanceDefaultIsMetric() {
        XCTAssertEqual(RowPlayFormatting.distance(5_000), RowPlayFormatting.distance(5_000, unit: .metric))
    }

    func testDistanceMarginPreservesPositiveSubMetreValue() {
        XCTAssertEqual(RowPlayFormatting.distanceMargin(0.3), "0.3 m")
        XCTAssertEqual(RowPlayFormatting.distanceMargin(0.1, unit: .imperial), "0.3 ft")
        XCTAssertEqual(RowPlayFormatting.distanceMargin(12), "12 m")
    }

    // MARK: - DistanceUnit

    func testDistanceUnitRawValueMetric() {
        XCTAssertEqual(DistanceUnit(rawValue: "metric"), .metric)
    }

    func testDistanceUnitRawValueImperial() {
        XCTAssertEqual(DistanceUnit(rawValue: "imperial"), .imperial)
    }

    func testDistanceUnitRawValueUnknownReturnsNil() {
        XCTAssertNil(DistanceUnit(rawValue: "unknown"))
        XCTAssertNil(DistanceUnit(rawValue: ""))
    }

    // MARK: - paceToWatts()

    func testPaceToWattsNormal() {
        let watts = RowPlayFormatting.paceToWatts(120)
        // 2.8 / (0.24)^3 ≈ 202.55
        XCTAssertEqual(watts, 202.55, accuracy: 0.01)
    }

    func testPaceToWattsFast() {
        let watts = RowPlayFormatting.paceToWatts(90)
        // Faster pace = more watts
        let slowWatts = RowPlayFormatting.paceToWatts(120)
        XCTAssertGreaterThan(watts, slowWatts)
    }

    func testPaceToWattsZeroReturnsZero() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(0), 0)
    }

    func testPaceToWattsNegativeReturnsZero() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(-1), 0)
    }

    func testPaceToWattsInfiniteReturnsZero() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(.infinity), 0)
    }

    // MARK: - paceToWatts(for:pacePer500m:)

    func testPaceToWattsForRower() {
        let rowerWatts = RowPlayFormatting.paceToWatts(for: .rower, pacePer500m: 120)
        let baseWatts = RowPlayFormatting.paceToWatts(120)
        XCTAssertEqual(rowerWatts, baseWatts)
    }

    func testPaceToWattsForSkiErg() {
        let skiWatts = RowPlayFormatting.paceToWatts(for: .skierg, pacePer500m: 120)
        let baseWatts = RowPlayFormatting.paceToWatts(120)
        XCTAssertEqual(skiWatts, baseWatts)
    }

    func testPaceToWattsForBike() {
        let bikeWatts = RowPlayFormatting.paceToWatts(for: .bike, pacePer500m: 120)
        let baseWatts = RowPlayFormatting.paceToWatts(120)
        XCTAssertEqual(bikeWatts, baseWatts / RowPlayFormatting.bikeWattsFromNormalizedPaceDivisor)
    }

    // MARK: - challengeDistance()

    func testChallengeDistanceRower() {
        let workout = Workout(
            id: 1, date: Date(), sport: .rower, distance: 5000, time: 1200,
            pace: 120, workoutType: "JustRow", hasStrokeData: false
        )
        XCTAssertEqual(RowPlayFormatting.challengeDistance(for: workout), 5000)
    }

    func testChallengeDistanceSkiErg() {
        let workout = Workout(
            id: 2, date: Date(), sport: .skierg, distance: 5000, time: 1200,
            pace: 120, workoutType: "JustRow", hasStrokeData: false
        )
        XCTAssertEqual(RowPlayFormatting.challengeDistance(for: workout), 5000)
    }

    func testChallengeDistanceBike() {
        let workout = Workout(
            id: 3, date: Date(), sport: .bike, distance: 10000, time: 1200,
            pace: 120, workoutType: "JustRow", hasStrokeData: false
        )
        XCTAssertEqual(RowPlayFormatting.challengeDistance(for: workout), 5000)
    }

    // MARK: - bikeWattsFromNormalizedPaceDivisor

    func testBikeWattsDivisor() {
        XCTAssertEqual(RowPlayFormatting.bikeWattsFromNormalizedPaceDivisor, 8.0)
    }

    // MARK: - Stress: time() boundaries

    func testTimeOneSecond() {
        XCTAssertEqual(RowPlayFormatting.time(1), "0:01")
    }

    func testTimeFiftyNineSeconds() {
        XCTAssertEqual(RowPlayFormatting.time(59), "0:59")
    }

    func testTimeSixtySeconds() {
        XCTAssertEqual(RowPlayFormatting.time(60), "1:00")
    }

    func testTimeSixtyOneSeconds() {
        XCTAssertEqual(RowPlayFormatting.time(61), "1:01")
    }

    func testTime59Minutes59Seconds() {
        XCTAssertEqual(RowPlayFormatting.time(3599), "59:59")
    }

    func testTimeThirtySixHundredSeconds() {
        XCTAssertEqual(RowPlayFormatting.time(3600), "1:00:00")
    }

    func testTimeTenthsForNormalMinuteValue() {
        XCTAssertEqual(RowPlayFormatting.time(125, tenths: true), "2:05.0")
    }

    // MARK: - Stress: pace() NaN

    func testPaceNaNReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.pace(.nan), "--:--")
    }

    // MARK: - Stress: distance() boundaries

    func testDistanceOneMetre() {
        XCTAssertEqual(RowPlayFormatting.distance(1), "1 m")
    }

    func testDistance999Metres() {
        XCTAssertEqual(RowPlayFormatting.distance(999), "999 m")
    }

    func testDistance1234Metres() {
        XCTAssertEqual(RowPlayFormatting.distance(1234), "1.23 km")
    }

    func testDistanceVeryLarge() {
        XCTAssertEqual(RowPlayFormatting.distance(1_000_000), "1000.00 km")
    }

    func testDistanceNegativeOneMetre() {
        XCTAssertEqual(RowPlayFormatting.distance(-1), "-1 m")
    }

    func testDistanceImperialOneMetre() {
        // 1 m ≈ 3 ft
        XCTAssertEqual(RowPlayFormatting.distance(1, unit: .imperial), "3 ft")
    }

    func testDistanceImperialVeryLarge() {
        XCTAssertEqual(RowPlayFormatting.distance(1_000_000, unit: .imperial), "621.37 mi")
    }

    func testDistanceImperialNaNReturnsPlaceholder() {
        XCTAssertEqual(RowPlayFormatting.distance(.nan, unit: .imperial), "--")
    }

    func testDistanceMetricAndImperialDiffer() {
        let metres: Double = 5_000
        let metric = RowPlayFormatting.distance(metres)
        let imperial = RowPlayFormatting.distance(metres, unit: .imperial)
        XCTAssertNotEqual(metric, imperial)
        XCTAssertTrue(metric.hasSuffix("km"))
        XCTAssertTrue(imperial.hasSuffix("mi"))
    }

    // MARK: - Stress: paceToWatts() edge cases

    func testPaceToWattsVerySlowPace() {
        // 600s/500m = very slow → watts ≈ 1.62
        let watts = RowPlayFormatting.paceToWatts(600)
        XCTAssertEqual(watts, 1.62, accuracy: 0.01)
        let normalWatts = RowPlayFormatting.paceToWatts(120)
        XCTAssertLessThan(watts, normalWatts)
    }

    func testPaceToWattsNaNReturnsZero() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(.nan), 0)
    }

    // MARK: - Stress: paceToWatts(for:pacePer500m:) invalid input

    func testPaceToWattsForRowerInvalidPace() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(for: .rower, pacePer500m: -1), 0)
    }

    func testPaceToWattsForSkiErgInvalidPace() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(for: .skierg, pacePer500m: -1), 0)
    }

    func testPaceToWattsForBikeInvalidPace() {
        XCTAssertEqual(RowPlayFormatting.paceToWatts(for: .bike, pacePer500m: -1), 0)
    }
}
