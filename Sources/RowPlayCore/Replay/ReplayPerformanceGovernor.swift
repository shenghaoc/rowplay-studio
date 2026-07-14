/// Portable, sticky adaptive-degradation governor for replay frame intervals.
///
/// The governor calibrates to the display's observed steady cadence before it
/// evaluates sustained slow frames. It only raises `level`; callers decide how
/// each level maps to a lower render-quality tier.
public struct ReplayPerformanceGovernor: Equatable, Sendable {
    public static let defaultFloorBudgetMilliseconds = 22.0
    public static let defaultCalibrationFrameCount = 30
    public static let defaultSustainedOverBudgetFrameCount = 60
    public static let defaultGraceFrameCount = 90
    public static let maximumAcceptedFrameIntervalMilliseconds = 250.0

    public let maximumLevel: Int
    public let floorBudgetMilliseconds: Double
    public let calibrationFrameCount: Int
    public let sustainedOverBudgetFrameCount: Int
    public let graceFrameCount: Int

    public private(set) var level = 0

    /// The calibrated working budget, or the floor while calibration is active.
    public var activeBudgetMilliseconds: Double {
        workingBudgetMilliseconds ?? floorBudgetMilliseconds
    }

    public var isCalibrated: Bool {
        calibrationSampleCount == calibrationFrameCount
    }

    // Internal deterministic seams for algorithm-level tests. These remain
    // portable scalar state and are not surfaced to application consumers.
    var smoothedFrameIntervalMilliseconds: Double {
        exponentialMovingAverageMilliseconds
    }

    var consecutiveOverBudgetFrames: Int {
        consecutiveOverBudgetFrameCount
    }

    var remainingGraceFrames: Int {
        remainingGraceFrameCount
    }

    private var calibrationSamples: [Double]
    private var calibrationSampleCount = 0
    private var workingBudgetMilliseconds: Double?
    private var exponentialMovingAverageMilliseconds = 0.0
    private var consecutiveOverBudgetFrameCount = 0
    private var remainingGraceFrameCount = 0

    public init(
        maximumLevel: Int,
        floorBudgetMilliseconds: Double = ReplayPerformanceGovernor.defaultFloorBudgetMilliseconds,
        calibrationFrameCount: Int = ReplayPerformanceGovernor.defaultCalibrationFrameCount,
        sustainedOverBudgetFrameCount: Int = ReplayPerformanceGovernor.defaultSustainedOverBudgetFrameCount,
        graceFrameCount: Int = ReplayPerformanceGovernor.defaultGraceFrameCount
    ) {
        self.maximumLevel = max(0, maximumLevel)
        self.floorBudgetMilliseconds = Self.positiveFinite(
            floorBudgetMilliseconds,
            fallback: Self.defaultFloorBudgetMilliseconds
        )
        self.calibrationFrameCount = max(1, calibrationFrameCount)
        self.sustainedOverBudgetFrameCount = max(1, sustainedOverBudgetFrameCount)
        self.graceFrameCount = max(0, graceFrameCount)
        calibrationSamples = Array(repeating: 0, count: self.calibrationFrameCount)
    }

    /// Feed one raw, unclamped frame interval in milliseconds.
    ///
    /// Returns the new level only when a one-step degradation fires. Invalid,
    /// non-positive, and app-background-sized intervals mutate no state.
    @discardableResult
    public mutating func sample(frameIntervalMilliseconds: Double) -> Int? {
        guard Self.isAcceptedFrameInterval(frameIntervalMilliseconds) else {
            return nil
        }

        if calibrationSampleCount < calibrationFrameCount {
            calibrationSamples[calibrationSampleCount] = frameIntervalMilliseconds
            calibrationSampleCount += 1
            if calibrationSampleCount == calibrationFrameCount {
                finishCalibration()
            }
            return nil
        }

        if remainingGraceFrameCount > 0 {
            remainingGraceFrameCount -= 1
            return nil
        }
        guard level < maximumLevel else { return nil }

        exponentialMovingAverageMilliseconds =
            exponentialMovingAverageMilliseconds * 0.9
                + frameIntervalMilliseconds * 0.1
        if exponentialMovingAverageMilliseconds > activeBudgetMilliseconds {
            consecutiveOverBudgetFrameCount += 1
            if consecutiveOverBudgetFrameCount >= sustainedOverBudgetFrameCount {
                level += 1
                consecutiveOverBudgetFrameCount = 0
                exponentialMovingAverageMilliseconds = 0
                remainingGraceFrameCount = graceFrameCount
                return level
            }
        } else {
            consecutiveOverBudgetFrameCount = 0
        }
        return nil
    }

    /// Clear calibration and degradation while preserving constructor policy.
    public mutating func reset() {
        level = 0
        calibrationSamples = Array(repeating: 0, count: calibrationFrameCount)
        calibrationSampleCount = 0
        workingBudgetMilliseconds = nil
        exponentialMovingAverageMilliseconds = 0
        consecutiveOverBudgetFrameCount = 0
        remainingGraceFrameCount = 0
    }

    public static func isAcceptedFrameInterval(_ milliseconds: Double) -> Bool {
        milliseconds.isFinite
            && milliseconds > 0
            && milliseconds <= maximumAcceptedFrameIntervalMilliseconds
    }

    private mutating func finishCalibration() {
        let sorted = calibrationSamples.sorted()
        // Match the tested web algorithm: even-sized windows use the upper
        // middle observation instead of averaging the two central values.
        let median = sorted[sorted.count >> 1]
        let cap = floorBudgetMilliseconds <= Double.greatestFiniteMagnitude / 2
            ? floorBudgetMilliseconds * 2
            : Double.greatestFiniteMagnitude
        workingBudgetMilliseconds = min(
            cap,
            max(floorBudgetMilliseconds, median * 1.6)
        )
        exponentialMovingAverageMilliseconds = median
    }

    private static func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}
