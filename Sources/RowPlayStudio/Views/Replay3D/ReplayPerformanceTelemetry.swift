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
}
