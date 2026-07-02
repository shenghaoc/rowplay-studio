import XCTest
@testable import RowPlayCore

/// Golden parity tests that assert native output matches web-verified values.
final class PerformancePredictorParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let input: Input
        let expected: [String: Double]

        struct Input: Decodable {
            let knownDistance: Int
            let knownSeconds: Double
        }
    }

    private var fixtures: [Fixture] = []

    override func setUpWithError() throws {
        fixtures = try ParityFixtureLoader.loadJSON([Fixture].self, from: "performance-predictor-parity")
    }

    func testFixturesLoaded() {
        XCTAssertFalse(fixtures.isEmpty, "Should load at least one fixture")
    }

    func testPerformancePredictorParity() {
        for fixture in fixtures {
            let predictions = PerformancePredictor.predictTimes(
                knownDistance: fixture.input.knownDistance,
                knownSeconds: fixture.input.knownSeconds
            )

            if fixture.expected.isEmpty {
                XCTAssertTrue(
                    predictions.isEmpty,
                    "\(fixture.name): expected empty predictions for zero inputs"
                )
                continue
            }

            for (keyStr, expectedValue) in fixture.expected {
                guard let distance = Int(keyStr) else {
                    XCTFail("\(fixture.name): invalid distance key \(keyStr)")
                    continue
                }
                let actual = predictions[distance]
                XCTAssertNotNil(actual, "\(fixture.name): missing prediction for \(distance)m")
                if let actual {
                    XCTAssertEqual(
                        actual, expectedValue, accuracy: expectedValue * 0.005,
                        "\(fixture.name): \(distance)m predicted \(actual), expected \(expectedValue)"
                    )
                }
            }
        }
    }

    func testPredictionTableStatusParity() {
        // Verify beaten/behind/untried classification for a known scenario
        let pbs: [(distance: Int, time: Double)] = [
            (distance: 2000, time: 410), // beaten the 420s prediction
            (distance: 5000, time: 1200), // behind the ~1150s prediction
        ]
        let table = PerformancePredictor.buildPredictionTable(
            knownDistance: 2000, knownSeconds: 420, personalBests: pbs
        )

        let row2k = table.first { $0.distance == 2000 }
        XCTAssertEqual(row2k?.status, .beaten, "2k PB of 410s should beat 420s prediction")

        let row5k = table.first { $0.distance == 5000 }
        XCTAssertEqual(row5k?.status, .behind, "5k PB of 1200s should be behind ~1150s prediction")

        let row10k = table.first { $0.distance == 10000 }
        XCTAssertEqual(row10k?.status, .untried, "10k has no PB → untried")
    }
}
