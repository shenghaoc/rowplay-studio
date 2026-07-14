/// One bounded replay-performance reporting window.
public struct ReplayPerformanceMetricsSnapshot: Equatable, Sendable {
    public let sampleCount: Int
    public let averageFrameIntervalMilliseconds: Double
    public let worstFrameIntervalMilliseconds: Double
    public let averageSceneUpdateDurationMilliseconds: Double
    public let worstSceneUpdateDurationMilliseconds: Double
    public let samplesAboveBudget: Int

    public init(
        sampleCount: Int,
        averageFrameIntervalMilliseconds: Double,
        worstFrameIntervalMilliseconds: Double,
        averageSceneUpdateDurationMilliseconds: Double,
        worstSceneUpdateDurationMilliseconds: Double,
        samplesAboveBudget: Int
    ) {
        self.sampleCount = sampleCount
        self.averageFrameIntervalMilliseconds = averageFrameIntervalMilliseconds
        self.worstFrameIntervalMilliseconds = worstFrameIntervalMilliseconds
        self.averageSceneUpdateDurationMilliseconds = averageSceneUpdateDurationMilliseconds
        self.worstSceneUpdateDurationMilliseconds = worstSceneUpdateDurationMilliseconds
        self.samplesAboveBudget = samplesAboveBudget
    }
}

/// Scalar, fixed-window replay-performance accumulator.
///
/// No per-frame sample history is retained. A completed snapshot is emitted at
/// the fixed window boundary, then all counters reset for the next window.
public struct ReplayPerformanceMetrics: Equatable, Sendable {
    public static let defaultWindowSize = 120

    public private(set) var sampleCount = 0

    private var averageFrameIntervalMilliseconds = 0.0
    private var worstFrameIntervalMilliseconds = 0.0
    private var averageSceneUpdateDurationMilliseconds = 0.0
    private var worstSceneUpdateDurationMilliseconds = 0.0
    private var samplesAboveBudget = 0

    public init() {}

    /// Record one paired playback-tick sample.
    ///
    /// Frame intervals use the governor's raw-sample validity boundary. Scene
    /// update durations may be zero, but negative/non-finite durations and
    /// invalid active budgets reject the whole pair so both averages retain the
    /// same denominator.
    @discardableResult
    public mutating func record(
        frameIntervalMilliseconds: Double,
        sceneUpdateDurationMilliseconds: Double,
        activeBudgetMilliseconds: Double
    ) -> ReplayPerformanceMetricsSnapshot? {
        guard ReplayPerformanceGovernor.isAcceptedFrameInterval(frameIntervalMilliseconds),
              sceneUpdateDurationMilliseconds.isFinite,
              sceneUpdateDurationMilliseconds >= 0,
              activeBudgetMilliseconds.isFinite,
              activeBudgetMilliseconds > 0 else {
            return nil
        }

        let nextCount = sampleCount + 1
        let divisor = Double(nextCount)
        averageFrameIntervalMilliseconds +=
            (frameIntervalMilliseconds - averageFrameIntervalMilliseconds) / divisor
        averageSceneUpdateDurationMilliseconds +=
            (sceneUpdateDurationMilliseconds - averageSceneUpdateDurationMilliseconds) / divisor
        worstFrameIntervalMilliseconds = max(
            worstFrameIntervalMilliseconds,
            frameIntervalMilliseconds
        )
        worstSceneUpdateDurationMilliseconds = max(
            worstSceneUpdateDurationMilliseconds,
            sceneUpdateDurationMilliseconds
        )
        if frameIntervalMilliseconds > activeBudgetMilliseconds {
            samplesAboveBudget += 1
        }
        sampleCount = nextCount

        guard sampleCount == Self.defaultWindowSize else { return nil }
        let snapshot = ReplayPerformanceMetricsSnapshot(
            sampleCount: sampleCount,
            averageFrameIntervalMilliseconds: averageFrameIntervalMilliseconds,
            worstFrameIntervalMilliseconds: worstFrameIntervalMilliseconds,
            averageSceneUpdateDurationMilliseconds: averageSceneUpdateDurationMilliseconds,
            worstSceneUpdateDurationMilliseconds: worstSceneUpdateDurationMilliseconds,
            samplesAboveBudget: samplesAboveBudget
        )
        reset()
        return snapshot
    }

    public mutating func reset() {
        sampleCount = 0
        averageFrameIntervalMilliseconds = 0
        worstFrameIntervalMilliseconds = 0
        averageSceneUpdateDurationMilliseconds = 0
        worstSceneUpdateDurationMilliseconds = 0
        samplesAboveBudget = 0
    }
}
