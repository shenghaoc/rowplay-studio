import Foundation

/// Context for selecting a ghost rival workout.
public struct GhostPickContext: Equatable, Sendable {
    public var id: Int
    public var distance: Double
    public var sport: Sport
    /// Total elapsed seconds (for time-axis comparability).
    public var time: TimeInterval
    /// Concept2 workout_type (for axis classification).
    public var workoutType: String?

    public init(
        id: Int,
        distance: Double,
        sport: Sport,
        time: TimeInterval,
        workoutType: String? = nil
    ) {
        self.id = id
        self.distance = distance
        self.sport = sport
        self.time = time
        self.workoutType = workoutType
    }
}

public enum GhostPick {
    /// Pick a meaningful default ghost rival: same comparability band, closest metres,
    /// then fastest pace (PB-like), then most recent session.
    public static func pickDefaultGhostCandidate(
        candidates: [Workout],
        current: GhostPickContext
    ) -> Workout? {
        let currentCtx = ComparableContext(
            sport: current.sport,
            distance: current.distance,
            time: current.time,
            workoutType: current.workoutType
        )
        let pool = candidates.filter { c in
            c.id != current.id && ComparabilityGuard.areComparable(
                currentCtx,
                ComparableContext(
                    sport: c.sport,
                    distance: c.distance,
                    time: c.time,
                    workoutType: c.workoutType
                )
            )
        }
        guard !pool.isEmpty else { return nil }

        // For time-axis pieces, rank by closeness in elapsed time.
        if ComparabilityGuard.classifyAxis(workoutType: current.workoutType) == .time {
            let target = current.time
            let ranked = pool.sorted { a, b in
                let dt = abs(a.time - target) - abs(b.time - target)
                if dt != 0 { return dt < 0 }
                if a.pace != b.pace { return a.pace < b.pace }
                return a.date > b.date
            }
            return ranked.first
        }

        // Distance-axis: prefer same distance band, closest metres, fastest pace, most recent.
        let band = WorkoutAnalytics.distanceBand(for: current.distance)
        let inBand = pool.filter {
            WorkoutAnalytics.distanceBand(for: $0.distance).key == band.key
        }
        let ranked = (inBand.isEmpty ? pool : inBand).sorted { a, b in
            let distDiff = abs(a.distance - current.distance) - abs(b.distance - current.distance)
            if distDiff != 0 { return distDiff < 0 }
            if a.pace != b.pace { return a.pace < b.pace }
            return a.date > b.date
        }
        return ranked.first
    }
}
