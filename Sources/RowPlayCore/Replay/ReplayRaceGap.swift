import Foundation

/// Pure, Sendable race-gap helpers for ghost-replay workflows.
///
/// Positive gap means the player is ahead; negative gap means the player is behind.
/// Approximate seconds use the player's current speed (500 / pacePer500m).
public enum ReplayRaceGap: Sendable {

    // MARK: - Gap Calculations

    /// Gap in metres between player and ghost. Positive means player is ahead.
    public static func raceGapMeters(playerDistance: Double, ghostDistance: Double) -> Double {
        let playerD = playerDistance.isFinite ? playerDistance : 0
        let ghostD = ghostDistance.isFinite ? ghostDistance : 0
        return playerD - ghostD
    }

    /// Approximate time gap in seconds using the player's current pace.
    /// Returns 0 when pace is non-positive or non-finite.
    public static func raceGapSeconds(gapMeters: Double, playerPacePer500m: Double) -> Double {
        guard gapMeters.isFinite else { return 0 }
        guard playerPacePer500m.isFinite, playerPacePer500m > 0 else { return 0 }
        let speedMps = 500.0 / playerPacePer500m
        return gapMeters / speedMps
    }

    // MARK: - Time Conversion

    /// Relative duration from first to last stroke timestamp.
    /// Returns 0 for empty arrays.
    public static func relativeDuration(strokes: [Stroke]) -> TimeInterval {
        guard let first = strokes.first?.t, let last = strokes.last?.t, first.isFinite, last.isFinite else {
            return 0
        }
        return max(0, last - first)
    }

    /// Convert elapsed replay time (relative to first stroke) to absolute stroke time.
    /// Clamps to [first.t, last.t]. Returns 0 for empty arrays.
    public static func absoluteTime(elapsed: TimeInterval, strokes: [Stroke]) -> TimeInterval {
        guard let first = strokes.first?.t, let last = strokes.last?.t, first.isFinite, last.isFinite else { return 0 }
        let safeElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let duration = max(0, last - first)
        let clamped = min(safeElapsed, duration)
        return first + clamped
    }

    // MARK: - Ghost Sampling

    /// Interpolated ghost frame at the player's current elapsed time.
    public static func ghostFrame(elapsed: TimeInterval, strokes: [Stroke]) -> ReplayFrame {
        guard !strokes.isEmpty else {
            return ReplayFrame(t: 0, d: 0, pace: 0, cadence: 0, watts: 0, progress: 0)
        }
        let absT = absoluteTime(elapsed: elapsed, strokes: strokes)
        return ReplaySample.sampleAt(strokes: strokes, t: absT)
    }

    /// Ghost distance at the player's current elapsed time.
    public static func ghostDistance(elapsed: TimeInterval, strokes: [Stroke]) -> Double {
        ghostFrame(elapsed: elapsed, strokes: strokes).d
    }
}
