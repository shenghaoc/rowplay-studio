import Foundation

/// Immutable stroke summaries shared by the 2D and 3D replay renderers.
///
/// Building these medians is O(N log N). Callers cache one value per workout
/// or genuine rival identity and keep aggregate construction out of frame-time
/// rendering paths.
public struct ReplayStrokePoseAggregates: Equatable, Sendable {
    public let context: ReplayStrokePoseContext
    public let medianHeartRate: Int

    public init(context: ReplayStrokePoseContext, medianHeartRate: Int) {
        self.context = context
        self.medianHeartRate = medianHeartRate
    }

    /// Returns nil when there are no strokes to summarize. Renderers use their
    /// deterministic sport fallback until a cached aggregate is available.
    public init?(strokes: [Stroke], sport: Sport) {
        guard !strokes.isEmpty else { return nil }

        let watts = strokes.map(\.watts)
        let distancePerStroke = strokes.indices.dropFirst().compactMap { index -> Double? in
            let delta = strokes[index].d - strokes[index - 1].d
            return delta.isFinite && delta > 0 ? delta : nil
        }
        let medianWatts = Self.roundedIntegerMedian(watts.map(Double.init))
        let medianHeartRate = Self.roundedIntegerMedian(
            strokes.compactMap(\.heartRate).map(Double.init)
        )

        context = ReplayStrokePoseContext(
            sport: sport,
            peakWatts: watts.max() ?? 0,
            medianWatts: medianWatts,
            medianDPS: Self.median(
                distancePerStroke,
                fallback: Self.defaultDistancePerStroke(for: sport)
            ),
            maxHR: strokes.compactMap(\.heartRate).max() ?? 0
        )
        self.medianHeartRate = medianHeartRate
    }

    /// Web-parity median: discard non-finite values, sort, and average the two
    /// middle values for an even sample count.
    public static func median(_ values: [Double], fallback: Double) -> Double {
        let finiteValues = values.filter(\.isFinite).sorted()
        guard !finiteValues.isEmpty else { return fallback }
        let middle = finiteValues.count / 2
        if finiteValues.count.isMultiple(of: 2) {
            return (finiteValues[middle - 1] + finiteValues[middle]) / 2
        }
        return finiteValues[middle]
    }

    public static func defaultDistancePerStroke(for sport: Sport) -> Double {
        switch sport {
        case .rower: 11
        case .skierg: 8
        case .bike: 5
        }
    }

    private static func roundedIntegerMedian(_ values: [Double]) -> Int {
        Int(exactly: median(values, fallback: 0).rounded()) ?? 0
    }
}
