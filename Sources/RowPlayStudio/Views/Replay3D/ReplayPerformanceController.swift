import Foundation
import Observation
import RowPlayCore

/// Scene-local coordinator for adaptive quality and bounded performance data.
/// Only `effectiveQuality` participates in SwiftUI observation; all frame-rate
/// bookkeeping stays outside the observation graph.
@MainActor
@Observable
final class ReplayPerformanceController {
    private struct PendingFrameSample {
        let generation: UInt64
        let frameIntervalMilliseconds: Double
        let activeBudgetMilliseconds: Double
    }

    private(set) var effectiveQuality: ReplayRenderQuality

    @ObservationIgnored private(set) var selectedQuality: ReplayRenderQuality
    @ObservationIgnored private var governor: ReplayPerformanceGovernor
    @ObservationIgnored private var metrics = ReplayPerformanceMetrics()
    @ObservationIgnored private var pendingFrameSample: PendingFrameSample?
    @ObservationIgnored private var lastFrameIntervalGeneration: UInt64?
    @ObservationIgnored private var lastSceneUpdateGeneration: UInt64?

    // Internal, non-observable seams used to verify generation de-duplication.
    @ObservationIgnored private(set) var acceptedFrameIntervalCount = 0
    @ObservationIgnored private(set) var recordedSceneUpdateCount = 0
    @ObservationIgnored private(set) var completedMetricsWindowCount = 0
    @ObservationIgnored private(set) var lastMetricsSnapshot: ReplayPerformanceMetricsSnapshot?

    init(selectedQuality: ReplayRenderQuality) {
        self.selectedQuality = selectedQuality
        effectiveQuality = selectedQuality
        governor = ReplayPerformanceGovernor(
            maximumLevel: selectedQuality.maximumDegradationLevel
        )
    }

    var governorLevel: Int { governor.level }

    var activeBudgetMilliseconds: Double {
        governor.activeBudgetMilliseconds
    }

    var metricsSampleCount: Int {
        metrics.sampleCount
    }

    var isAdaptiveReductionActive: Bool {
        effectiveQuality != selectedQuality
    }

    func resetForNewScene(selectedQuality: ReplayRenderQuality) {
        reset(selectedQuality: selectedQuality)
        ReplayPerformanceTelemetry.recordQualitySelection(selectedQuality)
    }

    func selectQuality(_ quality: ReplayRenderQuality) {
        reset(selectedQuality: quality)
        ReplayPerformanceTelemetry.recordQualitySelection(quality)
    }

    /// Accepts at most one raw frame interval for a playback-clock generation.
    /// Invalid and app-background-sized intervals do not create a paired scene
    /// sample and never reach the metrics accumulator.
    func recordFrameInterval(
        milliseconds: Double,
        playbackTickGeneration: UInt64
    ) {
        guard lastFrameIntervalGeneration != playbackTickGeneration else { return }
        lastFrameIntervalGeneration = playbackTickGeneration
        pendingFrameSample = nil

        guard milliseconds.isFinite,
              milliseconds > 0,
              milliseconds <= ReplayPerformanceGovernor
                  .maximumAcceptedFrameIntervalMilliseconds else {
            return
        }

        acceptedFrameIntervalCount &+= 1
        let previousLevel = governor.level
        let newLevel = governor.sample(frameIntervalMilliseconds: milliseconds)
        let budget = activeBudgetMilliseconds
        pendingFrameSample = PendingFrameSample(
            generation: playbackTickGeneration,
            frameIntervalMilliseconds: milliseconds,
            activeBudgetMilliseconds: budget
        )

        guard let newLevel, newLevel != previousLevel else { return }
        let degradedQuality = selectedQuality.degraded(by: newLevel)
        guard degradedQuality != effectiveQuality else { return }

        // A quality transition rebuilds the RealityKit graph. Discard the
        // transition tick and any partial metrics window so the next emitted
        // snapshot is attributable to exactly one effective tier.
        metrics.reset()
        pendingFrameSample = nil
        effectiveQuality = degradedQuality
        ReplayPerformanceTelemetry.recordAdaptiveDegradation(
            selectedQuality: selectedQuality,
            effectiveQuality: degradedQuality,
            governorLevel: newLevel
        )
    }

    func shouldMeasureSceneUpdate(
        playbackTickGeneration: UInt64
    ) -> Bool {
        pendingFrameSample?.generation == playbackTickGeneration
            && lastSceneUpdateGeneration != playbackTickGeneration
    }

    /// Pairs a measured RealityKit update with the raw interval from the same
    /// playback tick. Gesture- or control-driven refreshes reuse the generation
    /// and are therefore ignored.
    func recordSceneUpdateDuration(
        milliseconds: Double,
        playbackTickGeneration: UInt64
    ) {
        guard shouldMeasureSceneUpdate(
            playbackTickGeneration: playbackTickGeneration
        ), let sample = pendingFrameSample else {
            return
        }

        lastSceneUpdateGeneration = playbackTickGeneration
        pendingFrameSample = nil
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        recordedSceneUpdateCount &+= 1

        guard let snapshot = metrics.record(
            frameIntervalMilliseconds: sample.frameIntervalMilliseconds,
            sceneUpdateDurationMilliseconds: milliseconds,
            activeBudgetMilliseconds: sample.activeBudgetMilliseconds
        ) else {
            return
        }

        completedMetricsWindowCount &+= 1
        lastMetricsSnapshot = snapshot
        ReplayPerformanceTelemetry.recordMetricsWindow(
            snapshot,
            effectiveQuality: effectiveQuality,
            governorLevel: governor.level
        )
    }

    private func reset(selectedQuality: ReplayRenderQuality) {
        self.selectedQuality = selectedQuality
        if effectiveQuality != selectedQuality {
            effectiveQuality = selectedQuality
        }
        governor = ReplayPerformanceGovernor(
            maximumLevel: selectedQuality.maximumDegradationLevel
        )
        metrics.reset()
        pendingFrameSample = nil
        lastFrameIntervalGeneration = nil
        lastSceneUpdateGeneration = nil
        acceptedFrameIntervalCount = 0
        recordedSceneUpdateCount = 0
        completedMetricsWindowCount = 0
        lastMetricsSnapshot = nil
    }
}

/// Pure sampling policy shared by the 3D view and its regression tests.
/// Validation of interval bounds remains in `ReplayPerformanceGovernor`.
enum ReplayPerformanceSampling {
    static func frameIntervalMilliseconds(
        rawDelta: TimeInterval?,
        isPlaying: Bool,
        rendererMode: ReplayRendererMode
    ) -> Double? {
        guard isPlaying, rendererMode == .threeD, let rawDelta else { return nil }
        return rawDelta * 1_000
    }
}
