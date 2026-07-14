import XCTest
@testable import RowPlayCore

/// Parity-driven tests for ``ReplayRaceGap`` helpers backed by
/// `replay-race-gap-parity.json`.
final class ReplayRaceGapTests: XCTestCase {

    // MARK: - Parity Fixture Types

    private struct FixtureCase: Decodable {
        let label: String
        let playerD: Double?
        let ghostD: Double?
        let expectedGapM: Double?
        let playerPacePer500m: Double?
        let expectedGapSec: Double?
        let elapsed: TimeInterval?
        let ghostStrokes: [FixtureStroke]?
        let expectedGhostDistance: Double?
        let expectedRelativeDuration: Double?
        let expectedAbsoluteTime: TimeInterval?
        let expectedGhostTime: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case label, playerD, ghostD, expectedGapM, playerPacePer500m, expectedGapSec,
                 elapsed, ghostStrokes, expectedGhostDistance, expectedRelativeDuration,
                 expectedAbsoluteTime, expectedGhostTime
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            playerD = try container.decodeFiniteDoubleIfPresent(forKey: .playerD)
            ghostD = try container.decodeFiniteDoubleIfPresent(forKey: .ghostD)
            expectedGapM = try container.decodeFiniteDoubleIfPresent(forKey: .expectedGapM)
            playerPacePer500m = try container.decodeFiniteDoubleIfPresent(forKey: .playerPacePer500m)
            expectedGapSec = try container.decodeFiniteDoubleIfPresent(forKey: .expectedGapSec)
            elapsed = try container.decodeFiniteDoubleIfPresent(forKey: .elapsed)
            ghostStrokes = try container.decodeIfPresent([FixtureStroke].self, forKey: .ghostStrokes)
            expectedGhostDistance = try container.decodeFiniteDoubleIfPresent(forKey: .expectedGhostDistance)
            expectedRelativeDuration = try container.decodeFiniteDoubleIfPresent(forKey: .expectedRelativeDuration)
            expectedAbsoluteTime = try container.decodeFiniteDoubleIfPresent(forKey: .expectedAbsoluteTime)
            expectedGhostTime = try container.decodeFiniteDoubleIfPresent(forKey: .expectedGhostTime)
        }
    }

    private struct FixtureStroke: Decodable {
        let t: TimeInterval
        let d: Double
        let pace: TimeInterval
        let cadence: Double
        let heartRate: Int?
        let watts: Double
    }

    private struct FixtureFile: Decodable {
        let cases: [FixtureCase]
    }

    private static let fixtureResult = Result {
        try ParityFixtureLoader.loadJSON(FixtureFile.self, from: "replay-race-gap-parity")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = try Self.fixtureResult.get()
    }

    // MARK: - raceGapMeters

    func testRaceGapMetersParity() throws {
        for c in try Self.fixtureResult.get().cases {
            guard let playerD = c.playerD, let ghostD = c.ghostD, let expected = c.expectedGapM else {
                continue
            }
            let result = ReplayRaceGap.raceGapMeters(playerDistance: playerD, ghostDistance: ghostD)
            XCTAssertEqual(result, expected, accuracy: 0.01, "\(c.label)")
        }
    }

    // MARK: - raceGapSeconds

    func testRaceGapSecondsParity() throws {
        for c in try Self.fixtureResult.get().cases {
            guard let gapM = c.expectedGapM, let pace = c.playerPacePer500m, let expected = c.expectedGapSec else {
                continue
            }
            let result = ReplayRaceGap.raceGapSeconds(gapMeters: gapM, playerPacePer500m: pace)
            XCTAssertEqual(result, expected, accuracy: 0.01, "\(c.label)")
        }
    }

    // MARK: - ghostDistance

    func testGhostDistanceParity() throws {
        for c in try Self.fixtureResult.get().cases {
            guard let elapsed = c.elapsed, let strokes = c.ghostStrokes, let expected = c.expectedGhostDistance else {
                continue
            }
            let nativeStrokes = strokes.map { s in
                Stroke(t: s.t, d: s.d, pace: s.pace, cadence: s.cadence, heartRate: s.heartRate, watts: Int(s.watts))
            }
            let result = ReplayRaceGap.ghostDistance(elapsed: elapsed, strokes: nativeStrokes)
            XCTAssertEqual(result, expected, accuracy: 0.01, "\(c.label)")
        }
    }

    // MARK: - relativeDuration

    func testRelativeDurationParity() throws {
        for c in try Self.fixtureResult.get().cases {
            guard let strokes = c.ghostStrokes, let expected = c.expectedRelativeDuration else { continue }
            let nativeStrokes = strokes.map { s in
                Stroke(t: s.t, d: s.d, pace: s.pace, cadence: s.cadence, heartRate: s.heartRate, watts: Int(s.watts))
            }
            let result = ReplayRaceGap.relativeDuration(strokes: nativeStrokes)
            XCTAssertEqual(result, expected, accuracy: 0.01, "\(c.label)")
        }
    }

    // MARK: - Direct Unit Tests (degenerate inputs)

    func testRaceGapMetersDegenerateInput() {
        XCTAssertEqual(ReplayRaceGap.raceGapMeters(playerDistance: .nan, ghostDistance: .nan), 0)
        // Non-finite player distances are treated as 0 per the sanitizer guard.
        XCTAssertEqual(ReplayRaceGap.raceGapMeters(playerDistance: .infinity, ghostDistance: 0), 0)
        XCTAssertEqual(ReplayRaceGap.raceGapMeters(playerDistance: 0, ghostDistance: .infinity), 0)
    }

    func testRaceGapSecondsDegenerateInput() {
        XCTAssertEqual(ReplayRaceGap.raceGapSeconds(gapMeters: 100, playerPacePer500m: 0), 0)
        XCTAssertEqual(ReplayRaceGap.raceGapSeconds(gapMeters: 100, playerPacePer500m: -.infinity), 0)
        XCTAssertEqual(ReplayRaceGap.raceGapSeconds(gapMeters: .nan, playerPacePer500m: 120), 0)
    }

    func testRelativeDurationEmptyArrayReturnsZero() {
        XCTAssertEqual(ReplayRaceGap.relativeDuration(strokes: []), 0)
    }

    func testRelativeDurationSingleStrokeReturnsZero() {
        let s = Stroke(t: 10, d: 100, pace: 120, cadence: 28, watts: 200)
        XCTAssertEqual(ReplayRaceGap.relativeDuration(strokes: [s]), 0)
    }

    func testAbsoluteTimeEmptyArrayReturnsZero() {
        XCTAssertEqual(ReplayRaceGap.absoluteTime(elapsed: 10, strokes: []), 0)
    }

    func testAbsoluteTimeClampsToRange() {
        let strokes = [
            Stroke(t: 10, d: 100, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 20, d: 200, pace: 120, cadence: 28, watts: 200),
        ]
        XCTAssertEqual(ReplayRaceGap.absoluteTime(elapsed: -5, strokes: strokes), 10)
        XCTAssertEqual(ReplayRaceGap.absoluteTime(elapsed: 5, strokes: strokes), 15)
        XCTAssertEqual(ReplayRaceGap.absoluteTime(elapsed: 100, strokes: strokes), 20)
    }

    func testGhostFrameEmptyArrayReturnsZeroFrame() {
        let frame = ReplayRaceGap.ghostFrame(elapsed: 10, strokes: [])
        XCTAssertEqual(frame.d, 0)
        XCTAssertEqual(frame.t, 0)
    }

    func testGhostDistanceEmptyArrayReturnsZero() {
        XCTAssertEqual(ReplayRaceGap.ghostDistance(elapsed: 10, strokes: []), 0)
    }
}

private extension KeyedDecodingContainer {
    func decodeFiniteDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        // Handle Infinity/NaN encoded as strings
        if let str = try? decode(String.self, forKey: key) {
            switch str {
            case "Infinity", "+Infinity": return .infinity
            case "-Infinity": return -.infinity
            case "NaN": return .nan
            default: return Double(str)
            }
        }
        return try decode(Double.self, forKey: key)
    }
}
