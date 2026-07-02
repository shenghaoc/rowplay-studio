import XCTest
@testable import RowPlayCore

final class PerformancePredictorTests: XCTestCase {
    // MARK: - predictTimes

    func testPredictTimesFrom2k() {
        let predictions = PerformancePredictor.predictTimes(knownDistance: 2000, knownSeconds: 420)

        XCTAssertEqual(predictions.count, 7)
        XCTAssertEqual(predictions[2000] ?? 0, 420, accuracy: 0.01)
    }

    func testPredictTimesShorterDistanceIsFaster() {
        let predictions = PerformancePredictor.predictTimes(knownDistance: 2000, knownSeconds: 420)

        let t500 = predictions[500] ?? 0
        let t2000 = predictions[2000] ?? 0
        XCTAssertLessThan(t500, t2000)
    }

    func testPredictTimesLongerDistanceIsSlower() {
        let predictions = PerformancePredictor.predictTimes(knownDistance: 2000, knownSeconds: 420)

        let t5000 = predictions[5000] ?? 0
        let t2000 = predictions[2000] ?? 0
        XCTAssertGreaterThan(t5000, t2000)
    }

    func testPredictTimesPaulsLawFormula() {
        // time₂ = time₁ × (distance₂ / distance₁)^1.06
        let predictions = PerformancePredictor.predictTimes(knownDistance: 2000, knownSeconds: 420)
        let expected500 = 420.0 * pow(500.0 / 2000.0, 1.06)
        XCTAssertEqual(predictions[500] ?? 0, expected500, accuracy: 0.01)
    }

    func testPredictTimesZeroDistanceReturnsEmpty() {
        let predictions = PerformancePredictor.predictTimes(knownDistance: 0, knownSeconds: 420)
        XCTAssertTrue(predictions.isEmpty)
    }

    func testPredictTimesZeroSecondsReturnsEmpty() {
        let predictions = PerformancePredictor.predictTimes(knownDistance: 2000, knownSeconds: 0)
        XCTAssertTrue(predictions.isEmpty)
    }

    // MARK: - buildPredictionTable

    func testBuildPredictionTableMarksBeaten() {
        let pbs: [(distance: Int, time: Double)] = [
            (distance: 500, time: 80), // faster than predicted
        ]
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: pbs
        )

        let row500 = table.first { $0.distance == 500 }
        XCTAssertNotNil(row500)
        XCTAssertEqual(row500?.status, .beaten)
    }

    func testBuildPredictionTableMarksBehind() {
        let pbs: [(distance: Int, time: Double)] = [
            (distance: 500, time: 110), // slower than predicted
        ]
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: pbs
        )

        let row500 = table.first { $0.distance == 500 }
        XCTAssertNotNil(row500)
        XCTAssertEqual(row500?.status, .behind)
    }

    func testBuildPredictionTableMarksUntried() {
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: []
        )

        let row500 = table.first { $0.distance == 500 }
        XCTAssertEqual(row500?.status, .untried)
        XCTAssertNil(row500?.actualBestSeconds)
    }

    func testBuildPredictionTableKnownDistanceExactMatch() {
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: []
        )

        let row2k = table.first { $0.distance == 2000 }
        XCTAssertEqual(row2k?.predictedSeconds ?? 0, 420, accuracy: 0.01)
    }

    func testBuildPredictionTablePicksFastestPB() {
        let pbs: [(distance: Int, time: Double)] = [
            (distance: 500, time: 100),
            (distance: 500, time: 85), // this is the real PB
        ]
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: pbs
        )

        let row500 = table.first { $0.distance == 500 }
        XCTAssertEqual(row500?.actualBestSeconds, 85)
    }

    func testBuildPredictionTableReturnsAllDistances() {
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: []
        )
        XCTAssertEqual(table.count, 7)
    }

    func testBuildPredictionTableInvalidInputsReturnsEmpty() {
        let pbs: [(distance: Int, time: Double)] = [
            (distance: 500, time: 85),
        ]

        XCTAssertTrue(
            PerformancePredictor.buildPredictionTable(
                knownDistance: 0,
                knownSeconds: 420,
                personalBests: pbs
            ).isEmpty
        )
        XCTAssertTrue(
            PerformancePredictor.buildPredictionTable(
                knownDistance: 2000,
                knownSeconds: 0,
                personalBests: pbs
            ).isEmpty
        )
    }
}
