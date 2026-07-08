import Foundation
import XCTest
@testable import RowPlayCore

/// Validates native Concept2 decoding/mapping against sanitized golden fixtures
/// from the web repo. These tests do NOT call the real Concept2 API.
final class Concept2FixtureDecodingTests: XCTestCase {

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> Concept2GoldenFixture {
        try Concept2FixtureLoader.loadFixture(named: name)
    }

    private func mapDetail(from fixture: Concept2GoldenFixture) -> WorkoutDetail {
        let workout = Concept2Mapper.mapWorkout(fixture.rawResult)
        let strokes = Concept2Mapper.mapStrokes(fixture.rawStrokes, sport: workout.sport)
        let splits = Concept2Mapper.mapSplits(fixture.rawResult)
        return WorkoutDetail(workout: workout, strokes: strokes, splits: splits)
    }

    // MARK: - 1. Rower Steady

    func testDecodesRowerSteadyFixture() throws {
        let fixture = try loadFixture("rower-steady")
        let detail = mapDetail(from: fixture)

        // Summary parity
        XCTAssertEqual(detail.workout.id, 9001)
        XCTAssertEqual(detail.workout.sport, .rower)
        XCTAssertEqual(detail.workout.distance, 2000)
        XCTAssertEqual(detail.workout.time, 450, accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, 112.5, accuracy: 0.001)

        // Strokes present
        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // First stroke
        XCTAssertEqual(detail.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].d, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].pace, 108, accuracy: 0.001)

        // Last stroke
        let last = detail.strokes.count - 1
        XCTAssertEqual(detail.strokes[last].t, 6, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].d, 42.5, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].pace, 108.5, accuracy: 0.001)

        // Splits
        XCTAssertEqual(detail.splits.count, 1)
        XCTAssertEqual(detail.splits[0].time, 112.5, accuracy: 0.001)
        XCTAssertEqual(detail.splits[0].distance, 500)
        XCTAssertEqual(detail.splits[0].pace, 112.5, accuracy: 0.001)
    }

    // MARK: - 2. Rower Interval

    func testDecodesRowerIntervalFixture() throws {
        let fixture = try loadFixture("rower-interval")
        let detail = mapDetail(from: fixture)

        // Interval detection (fixture has workout.intervals)
        XCTAssertTrue(detail.workout.isInterval)

        // Summary parity
        XCTAssertEqual(detail.workout.id, 9004)
        XCTAssertEqual(detail.workout.sport, .rower)
        XCTAssertEqual(detail.workout.distance, 1000)
        XCTAssertEqual(detail.workout.time, 225, accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, 112.5, accuracy: 0.001)

        // All strokes present
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)
        XCTAssertEqual(detail.strokes.count, 10)

        // Interval metadata from fixture
        let rep2First = try XCTUnwrap(fixture.rep2FirstIndex)
        let rep1FinalT = try XCTUnwrap(fixture.rep1FinalT)
        let rep1FinalD = try XCTUnwrap(fixture.rep1FinalD)

        // Rep 1 final stroke
        let rep1Final = rep2First - 1
        XCTAssertEqual(detail.strokes[rep1Final].t, rep1FinalT, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[rep1Final].d, rep1FinalD, accuracy: 0.001)

        // Rep 2 first stroke — cumulative offset from rep 1
        XCTAssertEqual(detail.strokes[rep2First].t, rep1FinalT, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[rep2First].d, rep1FinalD, accuracy: 0.001)

        // Last stroke cumulative
        let last = detail.strokes.count - 1
        XCTAssertEqual(detail.strokes[last].t, 6.4, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].d, 32, accuracy: 0.001)

        // Interval splits
        XCTAssertEqual(detail.splits.count, 2)
        XCTAssertEqual(detail.splits[0].time, 112.5, accuracy: 0.001)
        XCTAssertEqual(detail.splits[0].distance, 500)
        XCTAssertEqual(detail.splits[1].time, 112.5, accuracy: 0.001)
        XCTAssertEqual(detail.splits[1].distance, 500)
    }

    // MARK: - 3. SkiErg

    func testDecodesSkiErgFixture() throws {
        let fixture = try loadFixture("ski-steady")
        let detail = mapDetail(from: fixture)

        XCTAssertEqual(detail.workout.id, 9003)
        XCTAssertEqual(detail.workout.sport, .skierg)
        XCTAssertEqual(detail.workout.distance, 6000)
        XCTAssertEqual(detail.workout.time, 1440, accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, 120, accuracy: 0.001)

        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // First stroke (paceDiv=1, same as rower)
        XCTAssertEqual(detail.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].d, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].pace, 144, accuracy: 0.001)

        // Last stroke
        let last = detail.strokes.count - 1
        XCTAssertEqual(detail.strokes[last].t, 9, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].d, 47.5, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].pace, 145, accuracy: 0.001)
    }

    // MARK: - 4. BikeErg

    func testDecodesBikeErgFixture() throws {
        let fixture = try loadFixture("bike-steady")
        let detail = mapDetail(from: fixture)

        XCTAssertEqual(detail.workout.id, 9002)
        XCTAssertEqual(detail.workout.sport, .bike)
        XCTAssertEqual(detail.workout.distance, 4000)
        XCTAssertEqual(detail.workout.time, 960, accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, 120, accuracy: 0.001)

        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // First stroke — pace halved from per-1000m to per-500m
        XCTAssertEqual(detail.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].d, 0, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[0].pace, 100, accuracy: 0.001)

        // Last stroke
        let last = detail.strokes.count - 1
        XCTAssertEqual(detail.strokes[last].t, 7.5, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].d, 60, accuracy: 0.001)
        XCTAssertEqual(detail.strokes[last].pace, 90, accuracy: 0.001)

        // BikeErg watts use divisor: pace 100 → 44W, pace 90 → 60W
        XCTAssertEqual(detail.strokes[0].watts, 44)
        XCTAssertEqual(detail.strokes[last].watts, 60)
    }

    // MARK: - 5. Stroke Monotonicity

    func testMappedStrokesAreMonotonic() throws {
        let fixtureNames = ["rower-steady", "rower-interval", "ski-steady", "bike-steady"]

        for name in fixtureNames {
            let fixture = try loadFixture(name)
            let sport = Sport.fromConcept2Type(fixture.rawResult.type)
            let strokes = Concept2Mapper.mapStrokes(fixture.rawStrokes, sport: sport)

            for i in 1..<strokes.count {
                XCTAssertGreaterThanOrEqual(
                    strokes[i].t, strokes[i - 1].t,
                    "[\(name)] stroke[\(i)].t (\(strokes[i].t)) < stroke[\(i-1)].t (\(strokes[i-1].t))"
                )
                XCTAssertGreaterThanOrEqual(
                    strokes[i].d, strokes[i - 1].d,
                    "[\(name)] stroke[\(i)].d (\(strokes[i].d)) < stroke[\(i-1)].d (\(strokes[i-1].d))"
                )
            }

            for (i, stroke) in strokes.enumerated() {
                XCTAssertGreaterThan(
                    stroke.pace, 0,
                    "[\(name)] stroke[\(i)].pace is not > 0"
                )
                XCTAssertGreaterThanOrEqual(
                    stroke.watts, 0,
                    "[\(name)] stroke[\(i)].watts is negative"
                )
            }
        }
    }

    // MARK: - 6. No Secrets

    func testFixturesDoNotContainSecrets() throws {
        let secretMarkers = [
            "Authorization",
            "Bearer ",
            "rp_tok",
            "SESSION_SECRET",
            "access_token",
            "refresh_token",
        ]

        let fixtureNames = ["rower-steady", "rower-interval", "ski-steady", "bike-steady"]

        for name in fixtureNames {
            let data = try Concept2FixtureLoader.loadRawData(named: name)
            let text = String(data: data, encoding: .utf8) ?? ""

            for marker in secretMarkers {
                XCTAssertFalse(
                    text.contains(marker),
                    "[\(name)] fixture contains secret marker: '\(marker)'"
                )
            }
        }
    }
}
