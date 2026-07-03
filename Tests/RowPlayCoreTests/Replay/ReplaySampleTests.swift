import XCTest
@testable import RowPlayCore

final class ReplaySampleTests: XCTestCase {
    // MARK: - Fixtures

    /// Simple 3-stroke ladder matching the web test fixture pattern.
    private var ladderStrokes: [Stroke] {
        [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, heartRate: 150, watts: 200),
            Stroke(t: 10, d: 50, pace: 110, cadence: 30, heartRate: 155, watts: 220),
            Stroke(t: 20, d: 150, pace: 100, cadence: 32, heartRate: 160, watts: 240)
        ]
    }

    // MARK: - sampleAt

    func testSampleAtReturnsZerosForEmptyStrokes() {
        let f = ReplaySample.sampleAt(strokes: [], t: 5)
        XCTAssertEqual(f.d, 0)
        XCTAssertEqual(f.pace, 0)
        XCTAssertEqual(f.progress, 0)
        XCTAssertEqual(f.cadence, 0)
        XCTAssertEqual(f.watts, 0)
    }

    func testSampleAtClampsBeforeFirstSample() {
        let strokes = ladderStrokes
        let f = ReplaySample.sampleAt(strokes: strokes, t: -1)
        XCTAssertEqual(f.pace, strokes[0].pace)
        XCTAssertEqual(f.d, strokes[0].d)
        XCTAssertEqual(f.progress, 0)
    }

    func testSampleAtClampsAfterLastSample() {
        let strokes = ladderStrokes
        let f = ReplaySample.sampleAt(strokes: strokes, t: 100)
        let last = strokes[strokes.count - 1]
        XCTAssertEqual(f.pace, last.pace)
        XCTAssertEqual(f.d, last.d)
        XCTAssertEqual(f.progress, 1)
    }

    func testSampleAtReturnsExactValuesOnStrokeTimestamps() {
        let strokes = ladderStrokes
        let mid = strokes[1]
        let f = ReplaySample.sampleAt(strokes: strokes, t: mid.t)
        XCTAssertEqual(f.pace, mid.pace)
        XCTAssertEqual(f.d, mid.d)
        XCTAssertEqual(f.cadence, mid.cadence)
        XCTAssertEqual(f.heartRate, mid.heartRate)
    }

    func testSampleAtInterpolatesMidStroke() {
        let strokes = ladderStrokes
        let f = ReplaySample.sampleAt(strokes: strokes, t: 15)
        XCTAssertEqual(f.t, 15)
        XCTAssertTrue(f.pace > 100 && f.pace < 120)
        XCTAssertTrue(f.d > 50 && f.d < 150)
        XCTAssertEqual(f.progress, 0.75, accuracy: 0.001)
    }

    func testSampleAtInterpolatesHeartRateWhenBothEndsHaveHR() {
        let strokes = ladderStrokes
        let f = ReplaySample.sampleAt(strokes: strokes, t: 15)
        XCTAssertNotNil(f.heartRate)
        XCTAssertTrue(f.heartRate! > 150 && f.heartRate! < 160)
    }

    func testSampleAtHandlesMissingHeartRateGracefully() {
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 10, d: 50, pace: 110, cadence: 30, heartRate: 155, watts: 220)
        ]
        let f = ReplaySample.sampleAt(strokes: strokes, t: 5)
        // Falls back to the available heart rate.
        XCTAssertEqual(f.heartRate, 155)
    }

    // MARK: - sampleIndexAt

    func testSampleIndexAtReturnsNegativeOneForEmptyStrokes() {
        XCTAssertEqual(ReplaySample.sampleIndexAt(strokes: [], t: 5), -1)
    }

    func testSampleIndexAtClampsBeforeFirstSample() {
        XCTAssertEqual(ReplaySample.sampleIndexAt(strokes: ladderStrokes, t: -1), 0)
    }

    func testSampleIndexAtClampsAfterLastSample() {
        XCTAssertEqual(ReplaySample.sampleIndexAt(strokes: ladderStrokes, t: 100), ladderStrokes.count - 1)
    }

    func testSampleIndexAtReturnsExactIndexOnTimestamps() {
        XCTAssertEqual(ReplaySample.sampleIndexAt(strokes: ladderStrokes, t: ladderStrokes[1].t), 1)
    }

    func testSampleIndexAtHoldsLowerBracketBetweenSamples() {
        let idx = ReplaySample.sampleIndexAt(strokes: ladderStrokes, t: 15)
        XCTAssertEqual(idx, 1)
        let f = ReplaySample.sampleAt(strokes: ladderStrokes, t: 15)
        XCTAssertNotEqual(f.pace, ladderStrokes[1].pace) // interpolated, not held
        XCTAssertEqual(ladderStrokes[idx].pace, ladderStrokes[1].pace) // held value
    }

    // MARK: - Ghost Coherence

    func testGhostCoherenceBothLanesAlignAtSameTime() {
        let player: [Stroke] = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 60, d: 250, pace: 118, cadence: 29, watts: 210),
            Stroke(t: 120, d: 500, pace: 116, cadence: 30, watts: 220)
        ]
        let ghost: [Stroke] = [
            Stroke(t: 0, d: 0, pace: 125, cadence: 26, watts: 180),
            Stroke(t: 60, d: 230, pace: 124, cadence: 27, watts: 185),
            Stroke(t: 120, d: 480, pace: 122, cadence: 28, watts: 190)
        ]

        for t in [0.0, 30.0, 60.0, 90.0, 120.0, 150.0] {
            let pf = ReplaySample.sampleAt(strokes: player, t: t)
            let gf = ReplaySample.sampleAt(strokes: ghost, t: t)
            XCTAssertEqual(pf.t, gf.t, "t mismatch at \(t)")
            XCTAssertEqual(pf.t, t, "frame t != requested t at \(t)")
        }
    }
}
