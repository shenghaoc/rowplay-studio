import Foundation
import XCTest
@testable import RowPlayCore

/// Validates native Concept2 decoding/mapping against sanitized golden fixtures
/// from the web repo. These tests do NOT call the real Concept2 API.
final class Concept2FixtureDecodingTests: XCTestCase {
    private static let prohibitedFixtureKeys: Set<String> = [
        "access_token",
        "api_key",
        "apikey",
        "authorization",
        "client_secret",
        "cookie",
        "device",
        "email",
        "first_name",
        "last_name",
        "password",
        "refresh_token",
        "serial_number",
        "session_secret",
        "set_cookie",
        "token",
        "username",
    ]

    private static let secretValueMarkers = [
        "bearer ",
        "github_pat_",
        "gho_",
        "ghp_",
        "rp_tok",
    ]

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
        let exp = fixture.expected

        // Summary parity (fixture-driven)
        XCTAssertEqual(detail.workout.id, fixture.rawResult.id)
        XCTAssertEqual(detail.workout.sport, Sport.fromConcept2Type(exp.result.sport))
        XCTAssertEqual(detail.workout.distance, try XCTUnwrap(exp.result.distance))
        XCTAssertEqual(detail.workout.time, try XCTUnwrap(exp.result.time), accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, try XCTUnwrap(exp.result.pace), accuracy: 0.001)
        XCTAssertFalse(detail.workout.isInterval)

        // Strokes present
        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // Expected strokes by index (fixture-driven)
        for expected in exp.strokes {
            let stroke = detail.strokes[expected.index]
            if let t = expected.t { XCTAssertEqual(stroke.t, t, accuracy: 0.001, "stroke[\(expected.index)].t") }
            if let d = expected.d { XCTAssertEqual(stroke.d, d, accuracy: 0.001, "stroke[\(expected.index)].d") }
            if let pace = expected.pace { XCTAssertEqual(stroke.pace, pace, accuracy: 0.001, "stroke[\(expected.index)].pace") }
        }

        // Expected splits by index (fixture-driven)
        XCTAssertEqual(detail.splits.count, exp.splits.count)
        for expected in exp.splits {
            let split = detail.splits[expected.index]
            if let time = expected.time { XCTAssertEqual(split.time, time, accuracy: 0.001, "split[\(expected.index)].time") }
            if let distance = expected.distance { XCTAssertEqual(split.distance, distance, accuracy: 0.001, "split[\(expected.index)].distance") }
            if let pace = expected.pace { XCTAssertEqual(split.pace, pace, accuracy: 0.001, "split[\(expected.index)].pace") }
        }
    }

    // MARK: - 2. Rower Interval

    func testDecodesRowerIntervalFixture() throws {
        let fixture = try loadFixture("rower-interval")
        let detail = mapDetail(from: fixture)
        let exp = fixture.expected

        // Interval detection
        XCTAssertTrue(detail.workout.isInterval)

        // Summary parity (fixture-driven)
        XCTAssertEqual(detail.workout.id, fixture.rawResult.id)
        XCTAssertEqual(detail.workout.sport, Sport.fromConcept2Type(exp.result.sport))
        XCTAssertEqual(detail.workout.distance, try XCTUnwrap(exp.result.distance))
        XCTAssertEqual(detail.workout.time, try XCTUnwrap(exp.result.time), accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, try XCTUnwrap(exp.result.pace), accuracy: 0.001)

        // All strokes present
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

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

        // Expected strokes by index (fixture-driven, includes pace at boundaries)
        for expected in exp.strokes {
            let stroke = detail.strokes[expected.index]
            if let t = expected.t { XCTAssertEqual(stroke.t, t, accuracy: 0.001, "stroke[\(expected.index)].t") }
            if let d = expected.d { XCTAssertEqual(stroke.d, d, accuracy: 0.001, "stroke[\(expected.index)].d") }
            if let pace = expected.pace { XCTAssertEqual(stroke.pace, pace, accuracy: 0.001, "stroke[\(expected.index)].pace") }
        }

        // Interval splits (fixture-driven)
        XCTAssertEqual(detail.splits.count, exp.splits.count)
        for expected in exp.splits {
            let split = detail.splits[expected.index]
            if let time = expected.time { XCTAssertEqual(split.time, time, accuracy: 0.001, "split[\(expected.index)].time") }
            if let distance = expected.distance { XCTAssertEqual(split.distance, distance, accuracy: 0.001, "split[\(expected.index)].distance") }
            if let pace = expected.pace { XCTAssertEqual(split.pace, pace, accuracy: 0.001, "split[\(expected.index)].pace") }
        }
    }

    // MARK: - 3. SkiErg

    func testDecodesSkiErgFixture() throws {
        let fixture = try loadFixture("ski-steady")
        let detail = mapDetail(from: fixture)
        let exp = fixture.expected

        XCTAssertEqual(detail.workout.id, fixture.rawResult.id)
        XCTAssertEqual(detail.workout.sport, Sport.fromConcept2Type(exp.result.sport))
        XCTAssertEqual(detail.workout.distance, try XCTUnwrap(exp.result.distance))
        XCTAssertEqual(detail.workout.time, try XCTUnwrap(exp.result.time), accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, try XCTUnwrap(exp.result.pace), accuracy: 0.001)
        XCTAssertFalse(detail.workout.isInterval)

        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // Expected strokes by index (fixture-driven)
        for expected in exp.strokes {
            let stroke = detail.strokes[expected.index]
            if let t = expected.t { XCTAssertEqual(stroke.t, t, accuracy: 0.001, "stroke[\(expected.index)].t") }
            if let d = expected.d { XCTAssertEqual(stroke.d, d, accuracy: 0.001, "stroke[\(expected.index)].d") }
            if let pace = expected.pace { XCTAssertEqual(stroke.pace, pace, accuracy: 0.001, "stroke[\(expected.index)].pace") }
        }
    }

    // MARK: - 4. BikeErg

    func testDecodesBikeErgFixture() throws {
        let fixture = try loadFixture("bike-steady")
        let detail = mapDetail(from: fixture)
        let exp = fixture.expected

        XCTAssertEqual(detail.workout.id, fixture.rawResult.id)
        XCTAssertEqual(detail.workout.sport, Sport.fromConcept2Type(exp.result.sport))
        XCTAssertEqual(detail.workout.distance, try XCTUnwrap(exp.result.distance))
        XCTAssertEqual(detail.workout.time, try XCTUnwrap(exp.result.time), accuracy: 0.001)
        XCTAssertEqual(detail.workout.pace, try XCTUnwrap(exp.result.pace), accuracy: 0.001)
        XCTAssertFalse(detail.workout.isInterval)

        XCTAssertFalse(detail.strokes.isEmpty)
        XCTAssertEqual(detail.strokes.count, fixture.rawStrokes.count)

        // Expected strokes by index (fixture-driven, includes pace)
        for expected in exp.strokes {
            let stroke = detail.strokes[expected.index]
            if let t = expected.t { XCTAssertEqual(stroke.t, t, accuracy: 0.001, "stroke[\(expected.index)].t") }
            if let d = expected.d { XCTAssertEqual(stroke.d, d, accuracy: 0.001, "stroke[\(expected.index)].d") }
            if let pace = expected.pace { XCTAssertEqual(stroke.pace, pace, accuracy: 0.001, "stroke[\(expected.index)].pace") }
        }

        // BikeErg watts use divisor: pace 100 → 44W, pace 90 → 60W
        // (hardcoded — watts not in fixture expected strokes)
        XCTAssertEqual(detail.strokes[0].watts, 44)
        let last = detail.strokes.count - 1
        XCTAssertEqual(detail.strokes[last].watts, 60)
    }

    // MARK: - 5. Stroke Monotonicity

    func testMappedStrokesAreMonotonic() throws {
        for name in try Concept2FixtureLoader.fixtureNames() {
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

    // MARK: - 6. Fixture Redaction

    func testFixturesDoNotContainSecretsOrPII() throws {
        for name in try Concept2FixtureLoader.fixtureNames() {
            let data = try Concept2FixtureLoader.loadRawData(named: name)
            let object = try JSONSerialization.jsonObject(with: data)
            let violations = fixtureRedactionViolations(in: object)

            XCTAssertTrue(
                violations.isEmpty,
                "[\(name)] fixture violates the redaction policy: \(violations.joined(separator: "; "))"
            )
        }
    }

    // MARK: - 7. Fixture Redaction Scanner

    func testFixtureRedactionScannerRejectsSensitiveKeysAndValues() {
        let unsafeFixture: [String: Any] = [
            "rawResult": [
                "client_secret": "not-a-real-secret",
                "comments": "Alice Example",
                "email": "athlete@example.com",
            ],
            "note": "Bearer rp_tok_not-a-real-token",
        ]

        let violations = fixtureRedactionViolations(in: unsafeFixture)

        XCTAssertTrue(violations.contains { $0.contains("client_secret") })
        XCTAssertTrue(violations.contains { $0.contains("comments") })
        XCTAssertTrue(violations.contains { $0.contains("email") })
        XCTAssertTrue(violations.contains { $0.contains("secret-like value") })
    }

    private func fixtureRedactionViolations(in value: Any, path: String = "$") -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                let childPath = "\(path).\(key)"
                let normalizedKey = key
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")

                var violations: [String] = []
                if Self.prohibitedFixtureKeys.contains(normalizedKey) {
                    violations.append("\(childPath) contains prohibited field '\(key)'")
                }
                if normalizedKey == "comments", let comment = child as? String, comment != "REDACTED" {
                    violations.append("\(childPath) must be omitted or exactly 'REDACTED'")
                }
                return violations + fixtureRedactionViolations(in: child, path: childPath)
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, child in
                fixtureRedactionViolations(in: child, path: "\(path)[\(index)]")
            }
        }

        guard let text = value as? String else { return [] }
        let lowercased = text.lowercased()
        var violations: [String] = []
        if Self.secretValueMarkers.contains(where: lowercased.contains) {
            violations.append("\(path) contains a secret-like value")
        }
        if text.range(
            of: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            violations.append("\(path) contains an email-like value")
        }
        return violations
    }
}
