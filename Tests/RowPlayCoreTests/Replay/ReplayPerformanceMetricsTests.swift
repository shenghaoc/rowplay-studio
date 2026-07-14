import XCTest
@testable import RowPlayCore

final class ReplayPerformanceMetricsTests: XCTestCase {
    func testSnapshotOccursExactlyAtOneHundredTwentyValidSamples() {
        var metrics = ReplayPerformanceMetrics()

        for _ in 0..<119 {
            XCTAssertNil(record(into: &metrics))
        }
        XCTAssertEqual(metrics.sampleCount, 119)

        let snapshot = record(into: &metrics)
        XCTAssertEqual(snapshot?.sampleCount, 120)
        XCTAssertEqual(metrics.sampleCount, 0)
    }

    func testAverageWorstAndOverBudgetValuesAreCorrect() throws {
        var metrics = ReplayPerformanceMetrics()
        var snapshot: ReplayPerformanceMetricsSnapshot?

        for _ in 0..<60 {
            snapshot = metrics.record(
                frameIntervalMilliseconds: 10,
                sceneUpdateDurationMilliseconds: 2,
                activeBudgetMilliseconds: 22
            )
        }
        for _ in 0..<60 {
            snapshot = metrics.record(
                frameIntervalMilliseconds: 30,
                sceneUpdateDurationMilliseconds: 4,
                activeBudgetMilliseconds: 22
            )
        }

        let completed = try XCTUnwrap(snapshot)
        XCTAssertEqual(completed.sampleCount, 120)
        XCTAssertEqual(completed.averageFrameIntervalMilliseconds, 20, accuracy: 1e-12)
        XCTAssertEqual(completed.worstFrameIntervalMilliseconds, 30, accuracy: 1e-12)
        XCTAssertEqual(
            completed.averageSceneUpdateDurationMilliseconds,
            3,
            accuracy: 1e-12
        )
        XCTAssertEqual(completed.worstSceneUpdateDurationMilliseconds, 4, accuracy: 1e-12)
        XCTAssertEqual(completed.samplesAboveBudget, 60)
    }

    func testInvalidSamplesAreIgnoredWithoutMutatingCounters() {
        var metrics = ReplayPerformanceMetrics()
        XCTAssertNil(record(into: &metrics))
        let before = metrics

        let invalidSamples: [(Double, Double, Double)] = [
            (.nan, 1, 22),
            (.infinity, 1, 22),
            (0, 1, 22),
            (-1, 1, 22),
            (250.01, 1, 22),
            (16, .nan, 22),
            (16, .infinity, 22),
            (16, -1, 22),
            (16, 1, .nan),
            (16, 1, 0),
            (16, 1, -1),
        ]
        for (frameInterval, updateDuration, budget) in invalidSamples {
            XCTAssertNil(metrics.record(
                frameIntervalMilliseconds: frameInterval,
                sceneUpdateDurationMilliseconds: updateDuration,
                activeBudgetMilliseconds: budget
            ))
            XCTAssertEqual(metrics, before)
        }
    }

    func testZeroSceneUpdateDurationIsAValidMeasurement() throws {
        var metrics = ReplayPerformanceMetrics()
        var snapshot: ReplayPerformanceMetricsSnapshot?

        for _ in 0..<ReplayPerformanceMetrics.defaultWindowSize {
            snapshot = metrics.record(
                frameIntervalMilliseconds: 16,
                sceneUpdateDurationMilliseconds: 0,
                activeBudgetMilliseconds: 22
            )
        }
        let completed = try XCTUnwrap(snapshot)

        XCTAssertEqual(completed.averageSceneUpdateDurationMilliseconds, 0)
        XCTAssertEqual(completed.worstSceneUpdateDurationMilliseconds, 0)
    }

    func testCountersResetAfterSnapshotAndBeginFreshWindow() throws {
        var metrics = ReplayPerformanceMetrics()
        var snapshot: ReplayPerformanceMetricsSnapshot?
        for _ in 0..<ReplayPerformanceMetrics.defaultWindowSize {
            snapshot = metrics.record(
                frameIntervalMilliseconds: 40,
                sceneUpdateDurationMilliseconds: 8,
                activeBudgetMilliseconds: 22
            )
        }
        _ = try XCTUnwrap(snapshot)

        XCTAssertEqual(metrics, ReplayPerformanceMetrics())
        XCTAssertNil(metrics.record(
            frameIntervalMilliseconds: 10,
            sceneUpdateDurationMilliseconds: 1,
            activeBudgetMilliseconds: 22
        ))
        XCTAssertEqual(metrics.sampleCount, 1)
    }

    func testManualResetClearsPartialWindow() {
        var metrics = ReplayPerformanceMetrics()
        for _ in 0..<25 {
            XCTAssertNil(record(into: &metrics))
        }

        metrics.reset()

        XCTAssertEqual(metrics, ReplayPerformanceMetrics())
    }

    @discardableResult
    private func record(
        into metrics: inout ReplayPerformanceMetrics
    ) -> ReplayPerformanceMetricsSnapshot? {
        metrics.record(
            frameIntervalMilliseconds: 16,
            sceneUpdateDurationMilliseconds: 2,
            activeBudgetMilliseconds: 22
        )
    }
}
