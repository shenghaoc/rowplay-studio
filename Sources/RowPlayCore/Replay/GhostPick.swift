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

public enum GhostPick: Sendable {
    /// Rank comparable past-session candidates for ghost replay.
    ///
    /// Excludes the current workout, candidates without stroke data, different sports,
    /// and candidates rejected by ``ComparabilityGuard``. Preserves distance-axis versus
    /// time-axis ranking behavior.
    ///
    /// Distance-axis ranking:
    /// 1. Matching distance band.
    /// 2. Closest distance.
    /// 3. Fastest pace.
    /// 4. Most recent date.
    /// 5. Stable workout-ID tie-break.
    ///
    /// Time-axis ranking:
    /// 1. Matching duration band.
    /// 2. Closest duration.
    /// 3. Fastest pace.
    /// 4. Most recent date.
    /// 5. Stable workout-ID tie-break.
    public static func rankedGhostCandidates(
        candidates: [Workout],
        current: GhostPickContext
    ) -> [Workout] {
        let currentCtx = ComparableContext(
            sport: current.sport,
            distance: current.distance,
            time: current.time,
            workoutType: current.workoutType
        )
        let pool = candidates.filter { c in
            c.id != current.id && c.hasStrokeData && ComparabilityGuard.areComparable(
                currentCtx,
                ComparableContext(
                    sport: c.sport,
                    distance: c.distance,
                    time: c.time,
                    workoutType: c.workoutType
                )
            )
        }
        guard !pool.isEmpty else { return [] }

        // For time-axis pieces, rank by closeness in elapsed time.
        if ComparabilityGuard.classifyAxis(workoutType: current.workoutType) == .time {
            let target = sanitizedTime(current.time)
            return pool.sorted { a, b in
                let dt = abs(sanitizedTime(a.time) - target) - abs(sanitizedTime(b.time) - target)
                if dt != 0 { return dt < 0 }
                let paceA = sanitizedPace(a.pace)
                let paceB = sanitizedPace(b.pace)
                if paceA != paceB { return paceA < paceB }
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
        }

        // Distance-axis: prefer same distance band, closest metres, fastest pace, most recent.
        let currentDistance = sanitizedDistance(current.distance)
        let band = WorkoutAnalytics.distanceBand(for: currentDistance)
        let inBand = pool.filter {
            WorkoutAnalytics.distanceBand(for: sanitizedDistance($0.distance)).key == band.key
        }
        let ranked = (inBand.isEmpty ? pool : inBand).sorted { a, b in
            let distDiff = abs(sanitizedDistance(a.distance) - currentDistance)
                - abs(sanitizedDistance(b.distance) - currentDistance)
            if distDiff != 0 { return distDiff < 0 }
            let paceA = sanitizedPace(a.pace)
            let paceB = sanitizedPace(b.pace)
            if paceA != paceB { return paceA < paceB }
            if a.date != b.date { return a.date > b.date }
            return a.id < b.id
        }
        return ranked
    }

    /// Pick a meaningful default ghost rival: ``rankedGhostCandidates(_:current:)``.first.
    public static func pickDefaultGhostCandidate(
        candidates: [Workout],
        current: GhostPickContext
    ) -> Workout? {
        rankedGhostCandidates(candidates: candidates, current: current).first
    }

    // MARK: - Sanitizers

    private static func sanitizedDistance(_ d: Double) -> Double {
        d.isFinite && d > 0 ? d : 1
    }

    private static func sanitizedTime(_ t: TimeInterval) -> TimeInterval {
        t.isFinite && t > 0 ? t : 1
    }

    private static func sanitizedPace(_ p: TimeInterval) -> TimeInterval {
        p.isFinite && p > 0 ? p : .greatestFiniteMagnitude
    }
}
