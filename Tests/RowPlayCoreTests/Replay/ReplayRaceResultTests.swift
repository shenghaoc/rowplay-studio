import XCTest
@testable import RowPlayCore

final class ReplayRaceResultTests: XCTestCase {
    private struct FixtureStroke: Decodable {
        let t: TimeInterval
        let d: Double
        let pace: TimeInterval
        let cadence: Double
        let watts: Double
    }

    private struct FixtureCase: Decodable {
        let label: String
        let axis: String
        let targetDistance: FlexibleDouble?
        let targetDuration: TimeInterval?
        let workoutType: String?
        let playerStrokes: [FixtureStroke]
        let rivalStrokes: [FixtureStroke]
        let expectOutcome: String?
        let expectTimeMargin: Double?
        let expectDistanceMargin: Double?
        let expectTimeMarginAbsent: Bool?
        let expectRivalDNF: Bool?
        let expectPlayerFinishTime: Double?
        let expectRivalFinishTime: Double?
        let expectNil: Bool?
    }

    /// Accepts a finite number or the string "NaN".
    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let text = try? container.decode(String.self), text.uppercased() == "NAN" {
                value = .nan
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected Double or NaN string"
                )
            }
        }
    }

    private struct FixtureFile: Decodable {
        let cases: [FixtureCase]
    }

    private static let fixtureResult = Result {
        try ParityFixtureLoader.loadJSON(FixtureFile.self, from: "replay-race-result-parity")
    }

    func testRaceResultParityFixture() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.cases {
            let playerStrokes = c.playerStrokes.map(toStroke)
            let rivalStrokes = c.rivalStrokes.map(toStroke)
            let workout = makeWorkout(from: c)
            let result = ReplayRaceResultCalculator.result(
                playerStrokes: playerStrokes,
                rivalStrokes: rivalStrokes,
                workout: workout
            )

            if c.expectNil == true {
                XCTAssertNil(result, c.label)
                continue
            }

            guard let result else {
                XCTFail("Expected result for \(c.label)")
                continue
            }

            if let outcome = c.expectOutcome {
                XCTAssertEqual(result.outcome.rawValue, outcome, c.label)
            }
            if let margin = c.expectTimeMargin {
                XCTAssertEqual(result.timeMargin ?? -1, margin, accuracy: 0.05, c.label)
            }
            if c.expectTimeMarginAbsent == true {
                XCTAssertNil(result.timeMargin, c.label)
            }
            if let margin = c.expectDistanceMargin {
                XCTAssertEqual(result.distanceMargin ?? -1, margin, accuracy: 0.5, c.label)
            }
            if let dnf = c.expectRivalDNF {
                XCTAssertEqual(result.rivalDidNotFinish, dnf, c.label)
            }
            if let finish = c.expectPlayerFinishTime {
                XCTAssertEqual(result.playerFinishTime ?? -1, finish, accuracy: 0.05, c.label)
            }
            if let finish = c.expectRivalFinishTime {
                XCTAssertEqual(result.rivalFinishTime ?? -1, finish, accuracy: 0.05, c.label)
            }

            // All reported numbers are finite and non-negative.
            if let tm = result.timeMargin {
                XCTAssertTrue(tm.isFinite && tm >= 0, c.label)
            }
            if let dm = result.distanceMargin {
                XCTAssertTrue(dm.isFinite && dm >= 0, c.label)
            }
        }
    }

    func testTimeCrossingUsesInterpolationNotEndpoint() {
        // Sparse 0→2000m over 480s; target 1000m crosses at 240s.
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 480, d: 2000, pace: 120, cadence: 28, watts: 200),
        ]
        let crossing = ReplayRaceResultCalculator.timeCrossingTarget(
            strokes: strokes,
            targetDistance: 1000
        )
        XCTAssertEqual(crossing ?? -1, 240, accuracy: 0.001)
    }

    func testTimeCrossingHandlesNonZeroOrigin() {
        let strokes = [
            Stroke(t: 100, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 340, d: 1000, pace: 120, cadence: 28, watts: 200),
        ]
        let crossing = ReplayRaceResultCalculator.timeCrossingTarget(
            strokes: strokes,
            targetDistance: 1000
        )
        XCTAssertEqual(crossing ?? -1, 240, accuracy: 0.001)
    }

    private func toStroke(_ s: FixtureStroke) -> Stroke {
        Stroke(
            t: s.t,
            d: s.d,
            pace: s.pace,
            cadence: s.cadence,
            watts: Int(s.watts.rounded())
        )
    }

    private func makeWorkout(from c: FixtureCase) -> Workout {
        let isTime = c.axis == "time"
        let distance: Double
        if let target = c.targetDistance {
            distance = target.value
        } else {
            distance = 2000
        }
        return Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 0),
            sport: .rower,
            distance: distance,
            time: c.targetDuration ?? 480,
            pace: 120,
            workoutType: c.workoutType ?? (isTime ? "JustRow" : "FixedDistanceIntervals"),
            hasStrokeData: true
        )
    }
}
