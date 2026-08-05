import OSLog
import RowPlayCore

/// Privacy-bounded unified logging for adaptive replay quality.
///
/// Events intentionally contain only quality tiers, governor state, sample
/// counts, and aggregate timing measurements. Workout and account data never
/// cross this boundary.
enum ReplayPerformanceTelemetry {
    private static let logger = Logger(
        subsystem: "com.shenghaoc.RowPlayStudio",
        category: "replay-performance"
    )

    static func recordQualitySelection(_ quality: ReplayRenderQuality) {
        logger.info(
            "quality selected tier=\(quality.rawValue, privacy: .public)"
        )
    }

    static func recordAdaptiveDegradation(
        selectedQuality: ReplayRenderQuality,
        effectiveQuality: ReplayRenderQuality,
        governorLevel: Int
    ) {
        logger.info(
            "quality degraded selected=\(selectedQuality.rawValue, privacy: .public) effective=\(effectiveQuality.rawValue, privacy: .public) level=\(governorLevel, privacy: .public)"
        )
    }

    static func recordMetricsWindow(
        _ snapshot: ReplayPerformanceMetricsSnapshot,
        effectiveQuality: ReplayRenderQuality,
        governorLevel: Int
    ) {
        logger.info(
            "metrics window tier=\(effectiveQuality.rawValue, privacy: .public) level=\(governorLevel, privacy: .public) samples=\(snapshot.sampleCount, privacy: .public) averageFrameMs=\(snapshot.averageFrameIntervalMilliseconds, privacy: .public) worstFrameMs=\(snapshot.worstFrameIntervalMilliseconds, privacy: .public) averageSceneMs=\(snapshot.averageSceneUpdateDurationMilliseconds, privacy: .public) worstSceneMs=\(snapshot.worstSceneUpdateDurationMilliseconds, privacy: .public) overBudget=\(snapshot.samplesAboveBudget, privacy: .public)"
        )
    }

    /// One privacy-safe acceptance summary. Scenario IDs are public catalog
    /// tokens only; no workout, account, token, or path data is logged.
    static func recordAcceptanceSummary(
        _ summary: ReplayAcceptanceMetrics.Summary,
        scenarioID: String?
    ) {
        let scenario = scenarioID ?? "unspecified"
        logger.info(
            "acceptance summary scenario=\(scenario, privacy: .public) samples=\(summary.sampleCount, privacy: .public) p50FrameMs=\(summary.p50FrameIntervalMilliseconds, privacy: .public) p95FrameMs=\(summary.p95FrameIntervalMilliseconds, privacy: .public) p99FrameMs=\(summary.p99FrameIntervalMilliseconds, privacy: .public) worstFrameMs=\(summary.worstFrameIntervalMilliseconds, privacy: .public) p95SceneMs=\(summary.p95SceneUpdateDurationMilliseconds, privacy: .public) overBudget=\(summary.samplesAboveBudget, privacy: .public) selected=\(summary.selectedQuality, privacy: .public) effective=\(summary.effectiveQuality, privacy: .public) degrade=\(summary.adaptiveDegradationCount, privacy: .public) rebuilds=\(summary.sceneRebuildCount, privacy: .public) fallbacks=\(summary.fallbackCount, privacy: .public) fallback=\(summary.fallbackCategory, privacy: .public) live=\(summary.livePresent, privacy: .public) rival=\(summary.rivalPresent, privacy: .public)"
        )
    }

    static func recordAcceptanceWriteFailure() {
        logger.error("acceptance metrics write failed category=output-directory")
    }
}
