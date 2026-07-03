import Foundation

/// Replay inspector helpers for examining stroke data.
public enum ReplayInspector {
    /// Metres per stroke at this instant; nil when pace or cadence is invalid.
    public static func distancePerStroke(pace: TimeInterval, cadence: Double) -> Double? {
        guard pace > 0, cadence > 0 else { return nil }
        // pace is per 500m (row/ski) or per 1000m (bike) in seconds.
        // speed = distance / time. For row/ski: speed = 500 / pace (m/s).
        // distance per stroke = speed * (60 / cadence) = 500 * 60 / (pace * cadence) = 30000 / (pace * cadence).
        let dps = 30_000 / (pace * cadence)
        return dps > 0 ? dps : nil
    }

    /// Split/interval index (0-based) for cumulative distance, or nil when no splits.
    public static func splitIndexAt(splits: [Split], distance distanceM: Double) -> Int? {
        guard !splits.isEmpty, distanceM >= 0 else { return nil }
        var cum = 0.0
        for (i, split) in splits.enumerated() {
            cum += split.distance
            if distanceM <= cum { return i }
        }
        return splits.count - 1
    }
}
