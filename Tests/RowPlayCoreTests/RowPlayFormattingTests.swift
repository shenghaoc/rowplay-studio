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
}
