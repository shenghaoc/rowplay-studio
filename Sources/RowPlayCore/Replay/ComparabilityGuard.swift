import Foundation

/// The axis a workout is measured along: fixed-distance or fixed-time.
public enum ComparabilityAxis: String, Sendable {
    case distance
    case time
}

/// Context required to evaluate comparability between two workouts.
public struct ComparableContext: Equatable, Sendable {
    public var sport: Sport
    /// Total distance in metres.
    public var distance: Double
    /// Total elapsed time in seconds.
    public var time: TimeInterval
    /// Concept2 workout_type string (may be absent).
    public var workoutType: String?

    public init(sport: Sport, distance: Double, time: TimeInterval, workoutType: String? = nil) {
        self.sport = sport
        self.distance = distance
        self.time = time
        self.workoutType = workoutType
    }
}

public enum ComparabilityGuard: Sendable {
    /// Concept2 workout_type markers that indicate a time-axis workout.
    private static let timeAxisMarkers = ["justrow", "fixedtime"]

    /// Map a Concept2 workout_type string to its comparability axis.
    ///
    /// Time-axis types are explicitly timed workouts; everything else — including
    /// nil / unknown strings, and calorie / watt-minute / variable-interval types —
    /// falls through to distance-axis.
    public static func classifyAxis(workoutType: String?) -> ComparabilityAxis {
        guard let workoutType else { return .distance }
        let upper = workoutType.lowercased()
        for marker in timeAxisMarkers {
            if upper.contains(marker) { return .time }
        }
        return .distance
    }

    /// Hard-block predicate. Returns true only when a and b are genuinely
    /// like-for-like: same sport, same axis (distance vs time), same axis-band.
    public static func areComparable(_ a: ComparableContext, _ b: ComparableContext) -> Bool {
        guard a.sport == b.sport else { return false }
        let axisA = classifyAxis(workoutType: a.workoutType)
        let axisB = classifyAxis(workoutType: b.workoutType)
        guard axisA == axisB else { return false }
        if axisA == .distance {
            return WorkoutAnalytics.distanceBand(for: a.distance).key
                == WorkoutAnalytics.distanceBand(for: b.distance).key
        }
        return WorkoutAnalytics.durationBand(for: a.time).key
            == WorkoutAnalytics.durationBand(for: b.time).key
    }
}
