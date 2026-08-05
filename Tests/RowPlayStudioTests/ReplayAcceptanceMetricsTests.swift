import XCTest
@testable import RowPlayStudio
import RowPlayCore

@MainActor
final class ReplayAcceptanceMetricsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ReplayAcceptanceMetricsStore.resetForTests()
    }

    override func tearDown() {
        ReplayAcceptanceMetricsStore.resetForTests()
        super.tearDown()
    }

    func testFixedCapacityBehavior() {
        var metrics = ReplayAcceptanceMetrics()
        metrics.enable(
            selectedQuality: .ultra,
            effectiveQuality: .ultra,
            livePresent: true,
            rivalPresent: true
        )
        for index in 0..<(ReplayAcceptanceMetrics.maximumSampleCount + 50) {
            metrics.record(
                frameIntervalMilliseconds: 16 + Double(index % 5),
                sceneUpdateDurationMilliseconds: 0.2,
                activeBudgetMilliseconds: 22
            )
        }
        XCTAssertEqual(metrics.sampleCount, ReplayAcceptanceMetrics.maximumSampleCount)
    }

    func testPercentileCalculation() {
        var metrics = ReplayAcceptanceMetrics()
        metrics.enable(
            selectedQuality: .medium,
            effectiveQuality: .medium,
            livePresent: true,
            rivalPresent: false
        )
        // 1...100 yields deterministic nearest-rank percentiles.
        let frames = (1...100).map { Double($0) }
        let scenes = (1...100).map { Double($0) / 10 }
        metrics.recordSyntheticSamples(
            frameIntervals: frames,
            sceneUpdates: scenes,
            budgetMilliseconds: 50
        )
        let summary = metrics.makeSummary()
        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.p50FrameIntervalMilliseconds, 50, accuracy: 0.001)
        XCTAssertEqual(summary.p95FrameIntervalMilliseconds, 95, accuracy: 0.001)
        XCTAssertEqual(summary.p99FrameIntervalMilliseconds, 99, accuracy: 0.001)
        XCTAssertEqual(summary.worstFrameIntervalMilliseconds, 100, accuracy: 0.001)
        XCTAssertEqual(summary.p95SceneUpdateDurationMilliseconds, 9.5, accuracy: 0.001)
        XCTAssertEqual(summary.samplesAboveBudget, 50)
    }

    func testInvalidNumericRejection() {
        var metrics = ReplayAcceptanceMetrics()
        metrics.enable(
            selectedQuality: .low,
            effectiveQuality: .low,
            livePresent: true,
            rivalPresent: false
        )
        metrics.record(
            frameIntervalMilliseconds: .nan,
            sceneUpdateDurationMilliseconds: 1,
            activeBudgetMilliseconds: 22
        )
        metrics.record(
            frameIntervalMilliseconds: -1,
            sceneUpdateDurationMilliseconds: 1,
            activeBudgetMilliseconds: 22
        )
        metrics.record(
            frameIntervalMilliseconds: 16,
            sceneUpdateDurationMilliseconds: .infinity,
            activeBudgetMilliseconds: 22
        )
        metrics.record(
            frameIntervalMilliseconds: 16,
            sceneUpdateDurationMilliseconds: 1,
            activeBudgetMilliseconds: 0
        )
        XCTAssertEqual(metrics.sampleCount, 0)
    }

    func testSceneFallbackRebuildCounters() {
        var metrics = ReplayAcceptanceMetrics()
        metrics.enable(
            selectedQuality: .high,
            effectiveQuality: .high,
            livePresent: true,
            rivalPresent: true
        )
        metrics.noteSceneRebuild()
        metrics.noteSceneRebuild()
        metrics.noteFallback(category: "procedural-athlete")
        metrics.noteAdaptiveDegradation()
        metrics.noteFirstSceneReadyLatencyMilliseconds(120)
        metrics.noteFirstAthleteReadyLatencyMilliseconds(180)
        metrics.noteFirstSceneReadyLatencyMilliseconds(999) // first-write wins
        let summary = metrics.makeSummary()
        XCTAssertEqual(summary.sceneRebuildCount, 2)
        XCTAssertEqual(summary.fallbackCount, 1)
        XCTAssertEqual(summary.fallbackCategory, "procedural-athlete")
        XCTAssertEqual(summary.adaptiveDegradationCount, 1)
        XCTAssertEqual(summary.firstSceneReadyLatencyMilliseconds, 120)
        XCTAssertEqual(summary.firstAthleteReadyLatencyMilliseconds, 180)
    }

    func testExactJSONSchemaAndPrivacyFieldRejection() {
        var metrics = ReplayAcceptanceMetrics()
        metrics.enable(
            selectedQuality: .ultra,
            effectiveQuality: .high,
            livePresent: true,
            rivalPresent: true
        )
        metrics.record(
            frameIntervalMilliseconds: 16.5,
            sceneUpdateDurationMilliseconds: 0.4,
            activeBudgetMilliseconds: 22
        )
        let object = metrics.makeSummary().jsonObject()
        let requiredKeys: Set<String> = [
            "sampleCount",
            "averageFrameIntervalMilliseconds",
            "p50FrameIntervalMilliseconds",
            "p95FrameIntervalMilliseconds",
            "p99FrameIntervalMilliseconds",
            "worstFrameIntervalMilliseconds",
            "averageSceneUpdateDurationMilliseconds",
            "p50SceneUpdateDurationMilliseconds",
            "p95SceneUpdateDurationMilliseconds",
            "p99SceneUpdateDurationMilliseconds",
            "worstSceneUpdateDurationMilliseconds",
            "samplesAboveBudget",
            "selectedQuality",
            "effectiveQuality",
            "adaptiveDegradationCount",
            "sceneRebuildCount",
            "fallbackCount",
            "fallbackCategory",
            "livePresent",
            "rivalPresent"
        ]
        XCTAssertTrue(requiredKeys.isSubset(of: Set(object.keys)))

        let forbidden = [
            "workoutID", "workoutId", "token", "account", "filename",
            "stroke", "path", "home", "user"
        ]
        for key in object.keys {
            for banned in forbidden {
                XCTAssertFalse(
                    key.lowercased().contains(banned),
                    "privacy field leaked: \(key)"
                )
            }
        }
    }

    func testNormalModeRecordsNothing() {
        var metrics = ReplayAcceptanceMetrics()
        // Disabled by default.
        metrics.record(
            frameIntervalMilliseconds: 16,
            sceneUpdateDurationMilliseconds: 0.2,
            activeBudgetMilliseconds: 22
        )
        metrics.noteSceneRebuild()
        metrics.noteFallback(category: "should-not-count")
        XCTAssertEqual(metrics.sampleCount, 0)
        XCTAssertEqual(metrics.makeSummary().sceneRebuildCount, 0)
        XCTAssertEqual(metrics.makeSummary().fallbackCount, 0)
    }

    func testStoreOnlyRecordsWhenEnabled() {
        ReplayAcceptanceMetricsStore.recordPairedSample(
            frameIntervalMilliseconds: 16,
            sceneUpdateDurationMilliseconds: 0.1,
            activeBudgetMilliseconds: 22
        )
        XCTAssertEqual(ReplayAcceptanceMetricsStore.metrics.sampleCount, 0)

        ReplayAcceptanceMetricsStore.beginScenario(
            scenarioID: "rower-3d-high-solo",
            selectedQuality: .high,
            effectiveQuality: .high,
            livePresent: true,
            rivalPresent: false
        )
        ReplayAcceptanceMetricsStore.recordPairedSample(
            frameIntervalMilliseconds: 17,
            sceneUpdateDurationMilliseconds: 0.2,
            activeBudgetMilliseconds: 22
        )
        XCTAssertEqual(ReplayAcceptanceMetricsStore.metrics.sampleCount, 1)
    }
}
