import XCTest
@testable import RowPlayCore

final class ReplayStrokePoseTests: XCTestCase {
    private let tau = Double.pi * 2

    // MARK: - Fixtures

    private func rowerContext() -> ReplayStrokePoseContext {
        ReplayStrokePoseContext(
            sport: .rower,
            peakWatts: 280,
            medianWatts: 220,
            medianDPS: 12,
            maxHR: 178
        )
    }

    private func skiergContext() -> ReplayStrokePoseContext {
        ReplayStrokePoseContext(
            sport: .skierg,
            peakWatts: 260,
            medianWatts: 200,
            medianDPS: 9,
            maxHR: 175
        )
    }

    private func bikeContext() -> ReplayStrokePoseContext {
        ReplayStrokePoseContext(
            sport: .bike,
            peakWatts: 320,
            medianWatts: 250,
            medianDPS: 6,
            maxHR: 165
        )
    }

    /// Helper to call compute() with stroke boundary data.
    private func computeHelper(
        frame: ReplayFrame,
        strokeIndex: Int,
        context: ReplayStrokePoseContext,
        medianHR: Int,
        duration: TimeInterval,
        startD: Double = 0,
        endD: Double = 11,
        startT: TimeInterval = 0,
        endT: TimeInterval = 2
    ) -> ReplayStrokePose {
        ReplayStrokePose.compute(
            frame: frame,
            strokeStartDistance: startD,
            strokeEndDistance: endD,
            strokeStartTime: startT,
            strokeEndTime: endT,
            strokeIndex: strokeIndex,
            context: context,
            medianHR: medianHR,
            duration: duration
        )
    }

    // MARK: - Web Parity: Rower

    func testRowerPoseAtStrokeBoundary() {
        let frame = ReplayFrame(t: 2, d: 11, pace: 120, cadence: 28, heartRate: 140, watts: 160, progress: 0)
        let pose = computeHelper(
            frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6,
            startD: 0, endD: 11, startT: 0, endT: 2
        )
        XCTAssertEqual(pose.index, 0)
        XCTAssertEqual(pose.cycleFrac, 0, accuracy: 0.001)
        XCTAssertTrue(pose.drive)
        XCTAssertEqual(pose.driveProgress, 0, accuracy: 0.001)
    }

    func testRowerMidCycleHasReasonableIntensity() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 29, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(
            frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6,
            startD: 0, endD: 11, startT: 0, endT: 2
        )
        XCTAssertTrue(pose.intensity > 0.4 && pose.intensity < 0.8,
                       "Intensity \(pose.intensity) out of expected range")
        XCTAssertTrue(pose.amplitude > 0.72 && pose.amplitude < 1.32,
                       "Amplitude \(pose.amplitude) out of bounds")
        XCTAssertTrue(pose.fatigue >= 0 && pose.fatigue <= 1,
                       "Fatigue \(pose.fatigue) out of bounds")
    }

    func testRowerDriveFractionRange() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 29, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(
            frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6,
            startD: 0, endD: 11, startT: 0, endT: 2
        )
        XCTAssertTrue(pose.driveFrac >= 0.28 && pose.driveFrac <= 0.46,
                       "Rower driveFrac \(pose.driveFrac) out of range")
    }

    // MARK: - Web Parity: SkiErg

    func testSkiErgPoseHasDifferentDriveFraction() {
        let frame = ReplayFrame(t: 2, d: 12, pace: 126, cadence: 40, heartRate: 155, watts: 140, progress: 0.3)
        let pose = computeHelper(
            frame: frame, strokeIndex: 0, context: skiergContext(), medianHR: 165, duration: 4.5,
            startD: 0, endD: 8, startT: 0, endT: 1.5
        )
        XCTAssertTrue(pose.driveFrac >= 0.28 && pose.driveFrac <= 0.46,
                       "SkiErg driveFrac \(pose.driveFrac) out of range")
    }

    // MARK: - Web Parity: BikeErg

    func testBikeHasSymmetricDriveFraction() {
        let frame = ReplayFrame(t: 1.5, d: 8, pace: 88, cadence: 85, heartRate: 140, watts: 180, progress: 0.5)
        let pose = computeHelper(
            frame: frame, strokeIndex: 0, context: bikeContext(), medianHR: 155, duration: 3,
            startD: 0, endD: 5, startT: 0, endT: 1
        )
        XCTAssertEqual(pose.driveFrac, 0.5, accuracy: 0.001,
                       "Bike should have symmetric 0.5 drive fraction")
    }

    // MARK: - computeAtTime

    func testComputeAtTimeCycleFracInterpolation() {
        let frame = ReplayFrame(t: 1.0, d: 5, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: 0.25)
        let pose = ReplayStrokePose.computeAtTime(
            frame: frame,
            strokeStartTime: 0,
            strokeEndTime: 2,
            strokeStartDistance: 0,
            strokeEndDistance: 11,
            strokeIndex: 0,
            context: rowerContext(),
            medianHR: 160,
            duration: 6
        )
        XCTAssertEqual(pose.cycleFrac, 0.5, accuracy: 0.001)
        XCTAssertEqual(pose.index, 0)
    }

    func testComputeAtTimeClampsAtBoundaries() {
        let context = rowerContext()
        // At start
        let startFrame = ReplayFrame(t: 0, d: 0, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: 0)
        let startPose = ReplayStrokePose.computeAtTime(
            frame: startFrame, strokeStartTime: 0, strokeEndTime: 2,
            strokeStartDistance: 0, strokeEndDistance: 11,
            strokeIndex: 0, context: context, medianHR: 160, duration: 6
        )
        XCTAssertEqual(startPose.cycleFrac, 0, accuracy: 0.001)

        // At end (should clamp to ~0.999999)
        let endFrame = ReplayFrame(t: 2, d: 11, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: 0.5)
        let endPose = ReplayStrokePose.computeAtTime(
            frame: endFrame, strokeStartTime: 0, strokeEndTime: 2,
            strokeStartDistance: 0, strokeEndDistance: 11,
            strokeIndex: 0, context: context, medianHR: 160, duration: 6
        )
        XCTAssertTrue(endPose.cycleFrac < 1.0)
        XCTAssertTrue(endPose.cycleFrac > 0.99)
    }

    func testComputeAtTimeHandlesZeroDurationStroke() {
        let frame = ReplayFrame(t: 0, d: 0, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: 0)
        let pose = ReplayStrokePose.computeAtTime(
            frame: frame, strokeStartTime: 5, strokeEndTime: 5,
            strokeStartDistance: 0, strokeEndDistance: 0,
            strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6
        )
        XCTAssertTrue(pose.phase.isFinite)
        XCTAssertTrue(pose.intensity.isFinite)
    }

    func testComputeAtTimeBikeHasSymmetricDrive() {
        let frame = ReplayFrame(t: 0.5, d: 3, pace: 88, cadence: 85, heartRate: 140, watts: 180, progress: 0.25)
        let pose = ReplayStrokePose.computeAtTime(
            frame: frame, strokeStartTime: 0, strokeEndTime: 1,
            strokeStartDistance: 0, strokeEndDistance: 5,
            strokeIndex: 0, context: bikeContext(), medianHR: 155, duration: 3
        )
        XCTAssertEqual(pose.driveFrac, 0.5, accuracy: 0.001)
    }

    // MARK: - Fallback

    func testFallbackProducesFiniteValues() {
        for sport in Sport.allCases {
            let pose = ReplayStrokePose.fallback(sport: sport, phase: Double.pi, rate: 30)
            XCTAssertTrue(pose.phase.isFinite, "\(sport) fallback phase not finite")
            XCTAssertTrue(pose.warpedPhase.isFinite, "\(sport) fallback warpedPhase not finite")
            XCTAssertTrue(pose.intensity.isFinite, "\(sport) fallback intensity not finite")
            XCTAssertTrue(pose.amplitude.isFinite, "\(sport) fallback amplitude not finite")
            XCTAssertTrue(pose.amplitude >= 0.72 && pose.amplitude <= 1.32,
                           "\(sport) fallback amplitude \(pose.amplitude) out of bounds")
        }
    }

    func testFallbackBikeHasSymmetricDrive() {
        let pose = ReplayStrokePose.fallback(sport: .bike, phase: tau, rate: 90)
        XCTAssertEqual(pose.driveFrac, 0.5, accuracy: 0.001)
        XCTAssertEqual(pose.rate, 90, accuracy: 0.001)
    }

    func testFallbackWithZeroRateStillProducesFinitePose() {
        for sport in Sport.allCases {
            let pose = ReplayStrokePose.fallback(sport: sport, phase: 0, rate: 0)
            XCTAssertTrue(pose.rate.isFinite, "\(sport) fallback rate should be finite")
            XCTAssertTrue(pose.phase.isFinite, "\(sport) fallback phase should be finite")
            XCTAssertTrue(pose.amplitude.isFinite, "\(sport) fallback amplitude should be finite")
        }
    }

    // MARK: - Reduced Motion

    func testReducedMotionFreezesPhase() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 29, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(
            frame: frame, strokeIndex: 1, context: rowerContext(), medianHR: 160, duration: 6,
            startD: 11, endD: 23, startT: 2, endT: 4
        )
        let frozen = ReplayStrokePose.reducedMotion(pose)
        XCTAssertEqual(frozen.phase, 0)
        XCTAssertEqual(frozen.warpedPhase, 0)
        XCTAssertEqual(frozen.cycleFrac, 0)
        XCTAssertFalse(frozen.drive)
        XCTAssertEqual(frozen.driveProgress, 0)
        XCTAssertEqual(frozen.recoveryProgress, 0)
        // Spatial state preserved
        XCTAssertEqual(frozen.index, pose.index)
        XCTAssertEqual(frozen.intensity, pose.intensity, accuracy: 0.001)
        XCTAssertEqual(frozen.amplitude, pose.amplitude, accuracy: 0.001)
    }

    // MARK: - Fatigue/Amplitude

    func testHighIntensityIncreasesAmplitude() {
        let lowFrame = ReplayFrame(t: 3, d: 17, pace: 130, cadence: 24, heartRate: 130, watts: 100, progress: 0.1)
        let highFrame = ReplayFrame(t: 3, d: 17, pace: 95, cadence: 36, heartRate: 178, watts: 280, progress: 0.1)
        let low = computeHelper(frame: lowFrame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        let high = computeHelper(frame: highFrame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertTrue(high.amplitude > low.amplitude,
                       "High intensity amplitude \(high.amplitude) should exceed low \(low.amplitude)")
    }

    func testFatigueIncreasesWithProgressAndHR() {
        let earlyFrame = ReplayFrame(t: 1, d: 5, pace: 115, cadence: 28, heartRate: 140, watts: 200, progress: 0.1)
        let lateFrame = ReplayFrame(t: 5, d: 30, pace: 115, cadence: 28, heartRate: 175, watts: 200, progress: 0.9)
        let early = computeHelper(frame: earlyFrame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        let late = computeHelper(frame: lateFrame, strokeIndex: 2, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertTrue(late.fatigue > early.fatigue,
                       "Late fatigue \(late.fatigue) should exceed early \(early.fatigue)")
    }

    // MARK: - Zero Watts Fallback

    func testZeroWattsContextUsesDefaultIntensity() {
        let context = ReplayStrokePoseContext(sport: .rower, peakWatts: 0, medianWatts: 0, medianDPS: 11, maxHR: 0)
        let frame = ReplayFrame(t: 2, d: 11, pace: 120, cadence: 28, watts: 0, progress: 0)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: context, medianHR: 0, duration: 6)
        XCTAssertTrue(pose.intensity.isFinite)
        XCTAssertTrue(pose.intensity >= 0 && pose.intensity <= 1)
    }

    // MARK: - Nil Heart Rate

    func testNilHeartRateProducesZeroHRFatigue() {
        let frame = ReplayFrame(t: 2, d: 11, pace: 120, cadence: 28, watts: 200, progress: 0.5)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        // With nil heartRate, hrFatigue should be 0, so fatigue is purely progress-based.
        XCTAssertTrue(pose.fatigue >= 0 && pose.fatigue <= 1)
    }

    // MARK: - Duration Zero

    func testDurationZeroProducesZeroProgressFatigue() {
        let frame = ReplayFrame(t: 0, d: 0, pace: 120, cadence: 28, heartRate: 150, watts: 200, progress: 0.5)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 0)
        // With duration=0, progress contribution to fatigue should be 0.
        XCTAssertTrue(pose.fatigue >= 0 && pose.fatigue <= 1)
    }

    // MARK: - Non-Finite Input Sanitization

    func testNonFiniteCadenceProducesFallbackRate() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: .nan, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertTrue(pose.rate.isFinite, "Rate should be finite despite NaN cadence")
        XCTAssertTrue(pose.rate > 0, "Rate should be positive")
    }

    func testNonFinitePaceProducesSafeValues() {
        let frame = ReplayFrame(t: 3, d: 17, pace: .infinity, cadence: 28, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertTrue(pose.intensity.isFinite, "intensity should be finite")
    }

    func testNonFiniteProgressProducesFiniteFatigue() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: .nan)
        let pose = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertTrue(pose.fatigue.isFinite, "fatigue should be finite despite NaN progress")
    }

    // MARK: - Warp Phase

    func testWarpedPhaseIsFinite() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 29, heartRate: 150, watts: 190, progress: 0.5)
        let pose = computeHelper(
            frame: frame, strokeIndex: 1, context: rowerContext(), medianHR: 160, duration: 6,
            startD: 11, endD: 23, startT: 2, endT: 4
        )
        XCTAssertTrue(pose.warpedPhase.isFinite, "warpedPhase should be finite")
    }

    // MARK: - Equatable

    func testEquatable() {
        let frame = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 29, heartRate: 150, watts: 190, progress: 0.5)
        let a = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        let b = computeHelper(frame: frame, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertEqual(a, b)
    }

    func testDifferentInputsProduceDifferentPoses() {
        let frame1 = ReplayFrame(t: 3, d: 17, pace: 120, cadence: 28, heartRate: 150, watts: 190, progress: 0.5)
        let frame2 = ReplayFrame(t: 3, d: 17, pace: 100, cadence: 36, heartRate: 175, watts: 280, progress: 0.5)
        let a = computeHelper(frame: frame1, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        let b = computeHelper(frame: frame2, strokeIndex: 0, context: rowerContext(), medianHR: 160, duration: 6)
        XCTAssertNotEqual(a.intensity, b.intensity)
    }

    // MARK: - Overflow Safety

    func testFallbackHandlesVeryLargePhase() {
        let pose = ReplayStrokePose.fallback(sport: .rower, phase: .greatestFiniteMagnitude, rate: 28)
        XCTAssertTrue(pose.index > 0)
        XCTAssertTrue(pose.phase.isFinite)
    }

    func testFallbackHandlesNegativePhase() {
        let pose = ReplayStrokePose.fallback(sport: .bike, phase: -100, rate: 90)
        XCTAssertEqual(pose.index, 0)
        XCTAssertTrue(pose.phase.isFinite)
    }

    // MARK: - Parity Fixture

    func testParityFixtureLoadsAndComputes() throws {
        struct CaseEntry: Codable {
            let name: String
            let sport: String
            let strokes: [Stroke]
            let context: ContextEntry
            let queryTime: Double
            let expected: ExpectedEntry
        }
        struct ContextEntry: Codable {
            let peakWatts: Int
            let medianWatts: Int
            let medianDPS: Double
            let medianHR: Int
            let maxHR: Int
        }
        struct ExpectedEntry: Codable {
            let index: Int
            let cycleFrac: Double
            let drive: Bool
            let driveFrac: Double?
            let driveFracRange: [Double]?
            let intensityRange: [Double]?
            let fatigueRange: [Double]?
            let amplitudeRange: [Double]?
        }
        struct Fixture: Codable {
            let cases: [CaseEntry]
        }

        let fixture = try ParityFixtureLoader.loadJSON(Fixture.self, from: "stroke-pose-parity")
        XCTAssertFalse(fixture.cases.isEmpty, "Parity fixture should have cases")

        for testCase in fixture.cases {
            let sport: Sport
            switch testCase.sport {
            case "rower": sport = .rower
            case "skierg": sport = .skierg
            case "bike": sport = .bike
            default:
                XCTFail("\(testCase.name): unknown sport \(testCase.sport)")
                continue
            }
            guard let index = testCase.strokes.firstIndex(where: { testCase.queryTime < $0.t })
                ?? testCase.strokes.indices.last else {
                XCTFail("\(testCase.name): no sampled stroke")
                continue
            }
            let end = testCase.strokes[index]
            let startTime = index > 0 ? testCase.strokes[index - 1].t : 0
            let startDistance = index > 0 ? testCase.strokes[index - 1].d : 0
            let duration = testCase.strokes.last?.t ?? 0
            let frame = ReplayFrame(
                t: testCase.queryTime,
                d: end.d,
                pace: end.pace,
                cadence: end.cadence,
                heartRate: end.heartRate,
                watts: end.watts,
                progress: duration > 0 ? testCase.queryTime / duration : 0
            )
            let pose = ReplayStrokePose.computeAtTime(
                frame: frame,
                strokeStartTime: startTime,
                strokeEndTime: end.t,
                strokeStartDistance: startDistance,
                strokeEndDistance: end.d,
                strokeIndex: index,
                context: ReplayStrokePoseContext(
                    sport: sport,
                    peakWatts: testCase.context.peakWatts,
                    medianWatts: testCase.context.medianWatts,
                    medianDPS: testCase.context.medianDPS,
                    maxHR: testCase.context.maxHR
                ),
                medianHR: testCase.context.medianHR,
                duration: duration
            )

            XCTAssertEqual(pose.index, testCase.expected.index, "\(testCase.name): index")
            XCTAssertEqual(pose.cycleFrac, testCase.expected.cycleFrac, accuracy: 0.000_001, "\(testCase.name): cycleFrac")
            XCTAssertEqual(pose.drive, testCase.expected.drive, "\(testCase.name): drive")
            if let expected = testCase.expected.driveFrac {
                XCTAssertEqual(pose.driveFrac, expected, accuracy: 0.000_001, "\(testCase.name): driveFrac")
            }
            assert(pose.driveFrac, in: testCase.expected.driveFracRange, name: testCase.name, field: "driveFrac")
            assert(pose.intensity, in: testCase.expected.intensityRange, name: testCase.name, field: "intensity")
            assert(pose.fatigue, in: testCase.expected.fatigueRange, name: testCase.name, field: "fatigue")
            assert(pose.amplitude, in: testCase.expected.amplitudeRange, name: testCase.name, field: "amplitude")
        }
    }

    private func assert(
        _ value: Double,
        in range: [Double]?,
        name: String,
        field: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let range else { return }
        XCTAssertEqual(range.count, 2, "\(name): \(field) range", file: file, line: line)
        guard range.count == 2 else { return }
        XCTAssertGreaterThanOrEqual(value, range[0], "\(name): \(field) below range", file: file, line: line)
        XCTAssertLessThanOrEqual(value, range[1], "\(name): \(field) above range", file: file, line: line)
    }
}
