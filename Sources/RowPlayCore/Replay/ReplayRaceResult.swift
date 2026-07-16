import Foundation

/// Outcome of a completed replay race.
public enum ReplayRaceOutcome: String, Codable, Sendable, Equatable {
    case playerWon
    case rivalWon
    case tie
}

/// Deterministic race result independent of SwiftUI rendering.
///
/// All numeric fields are finite and non-negative. Time margin is absent for
/// time-axis races. Distance races that never complete for the player produce
/// no result.
public struct ReplayRaceResult: Equatable, Sendable {
    public var outcome: ReplayRaceOutcome
    public var axis: ComparabilityAxis
    /// Absolute time margin in seconds when meaningful (distance-axis races).
    public var timeMargin: TimeInterval?
    /// Absolute distance margin in metres.
    public var distanceMargin: Double?
    /// True when the rival never reached a distance-axis target.
    public var rivalDidNotFinish: Bool
    /// Player finish time (relative) when available.
    public var playerFinishTime: TimeInterval?
    /// Rival finish time (relative) when available.
    public var rivalFinishTime: TimeInterval?
    /// Player distance at decision point.
    public var playerDistance: Double?
    /// Rival distance at decision point.
    public var rivalDistance: Double?

    public init(
        outcome: ReplayRaceOutcome,
        axis: ComparabilityAxis,
        timeMargin: TimeInterval? = nil,
        distanceMargin: Double? = nil,
        rivalDidNotFinish: Bool = false,
        playerFinishTime: TimeInterval? = nil,
        rivalFinishTime: TimeInterval? = nil,
        playerDistance: Double? = nil,
        rivalDistance: Double? = nil
    ) {
        self.outcome = outcome
        self.axis = axis
        self.timeMargin = Self.sanitizedNonNegative(timeMargin)
        self.distanceMargin = Self.sanitizedNonNegative(distanceMargin)
        self.rivalDidNotFinish = rivalDidNotFinish
        self.playerFinishTime = Self.sanitizedNonNegative(playerFinishTime)
        self.rivalFinishTime = Self.sanitizedNonNegative(rivalFinishTime)
        self.playerDistance = Self.sanitizedNonNegative(playerDistance)
        self.rivalDistance = Self.sanitizedNonNegative(rivalDistance)
    }

    private static func sanitizedNonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Pure race-result calculation for distance- and time-axis workouts.
public enum ReplayRaceResultCalculator: Sendable {
    /// Distance-axis finish-time tie tolerance (seconds).
    public static let distanceTimeTieTolerance: TimeInterval = 0.05
    /// Time-axis distance tie tolerance (metres).
    public static let timeDistanceTieTolerance: Double = 0.5

    /// Compute a completed race result, or `nil` when the player never finishes.
    ///
    /// - Parameters:
    ///   - playerStrokes: Primary workout strokes.
    ///   - rivalStrokes: Rival strokes.
    ///   - workout: Primary workout summary (axis, target distance/duration).
    public static func result(
        playerStrokes: [Stroke],
        rivalStrokes: [Stroke],
        workout: Workout
    ) -> ReplayRaceResult? {
        let axis = ComparabilityGuard.classifyAxis(workoutType: workout.workoutType)
        switch axis {
        case .distance:
            return distanceAxisResult(
                playerStrokes: playerStrokes,
                rivalStrokes: rivalStrokes,
                targetDistance: workout.distance
            )
        case .time:
            return timeAxisResult(
                playerStrokes: playerStrokes,
                rivalStrokes: rivalStrokes,
                targetDuration: workout.time
            )
        }
    }

    // MARK: - Distance axis

    /// First interpolated relative time at which the trace crosses `targetDistance`.
    ///
    /// Uses linear interpolation between consecutive samples. Does not simply
    /// compare array endpoint timestamps. Returns `nil` when the trace never
    /// reaches the target.
    public static func timeCrossingTarget(
        strokes: [Stroke],
        targetDistance: Double
    ) -> TimeInterval? {
        guard targetDistance.isFinite, targetDistance > 0, strokes.count >= 2 else { return nil }

        let originT = strokes[0].t
        guard originT.isFinite else { return nil }

        // Already past or at target at first sample.
        if strokes[0].d.isFinite, strokes[0].d >= targetDistance {
            return 0
        }

        for i in 1..<strokes.count {
            let prev = strokes[i - 1]
            let curr = strokes[i]
            guard prev.t.isFinite, curr.t.isFinite, prev.d.isFinite, curr.d.isFinite else {
                continue
            }
            // Skip non-forward or invalid segments.
            if curr.t < prev.t { continue }

            if prev.d < targetDistance && curr.d >= targetDistance {
                guard let frac = unitInterpolationFraction(
                    from: prev.d,
                    to: curr.d,
                    target: targetDistance
                ) else {
                    continue
                }
                let safeFrac = max(0, min(1, frac))
                let deltaT = curr.t - prev.t
                let absolute: TimeInterval
                if deltaT.isFinite {
                    absolute = prev.t + safeFrac * deltaT
                } else {
                    // A finite interval can overflow when its endpoints have
                    // opposite signs. The weighted form keeps that midpoint
                    // representable without forming the overflowing delta.
                    absolute = prev.t * (1 - safeFrac) + curr.t * safeFrac
                }
                let relative = absolute - originT
                return relative.isFinite && relative >= 0 ? relative : nil
            }
        }
        return nil
    }

    private static func unitInterpolationFraction(
        from start: Double,
        to end: Double,
        target: Double
    ) -> Double? {
        let delta = end - start
        if delta.isFinite, delta > 0 {
            let fraction = (target - start) / delta
            return fraction.isFinite ? fraction : nil
        }

        // Opposite-sign finite endpoints can produce an infinite subtraction.
        // Scaling first preserves their relative positions in a bounded range.
        let scale = max(abs(start), abs(end), abs(target))
        guard scale.isFinite, scale > 0 else { return nil }
        let scaledStart = start / scale
        let scaledEnd = end / scale
        let scaledTarget = target / scale
        let scaledDelta = scaledEnd - scaledStart
        guard scaledDelta.isFinite, scaledDelta > 0 else { return nil }
        let fraction = (scaledTarget - scaledStart) / scaledDelta
        return fraction.isFinite ? fraction : nil
    }

    private static func distanceAxisResult(
        playerStrokes: [Stroke],
        rivalStrokes: [Stroke],
        targetDistance: Double
    ) -> ReplayRaceResult? {
        guard targetDistance.isFinite, targetDistance > 0 else { return nil }
        guard let playerFinish = timeCrossingTarget(
            strokes: playerStrokes,
            targetDistance: targetDistance
        ) else {
            // Player never reaches target — no completed verdict.
            return nil
        }

        guard let rivalFinish = timeCrossingTarget(
            strokes: rivalStrokes,
            targetDistance: targetDistance
        ) else {
            // Rival DNF — player wins. Distance shortfall at player finish.
            let rivalDist = distanceAtRelativeTime(
                strokes: rivalStrokes,
                relativeTime: playerFinish
            )
            let shortfall = max(0, targetDistance - rivalDist)
            return ReplayRaceResult(
                outcome: .playerWon,
                axis: .distance,
                timeMargin: nil,
                distanceMargin: shortfall,
                rivalDidNotFinish: true,
                playerFinishTime: playerFinish,
                rivalFinishTime: nil,
                playerDistance: targetDistance,
                rivalDistance: rivalDist
            )
        }

        let delta = playerFinish - rivalFinish
        let absDelta = abs(delta)

        if absDelta <= distanceTimeTieTolerance {
            return ReplayRaceResult(
                outcome: .tie,
                axis: .distance,
                timeMargin: 0,
                distanceMargin: 0,
                rivalDidNotFinish: false,
                playerFinishTime: playerFinish,
                rivalFinishTime: rivalFinish,
                playerDistance: targetDistance,
                rivalDistance: targetDistance
            )
        }

        if delta < 0 {
            // Player faster.
            let rivalAtPlayerFinish = distanceAtRelativeTime(
                strokes: rivalStrokes,
                relativeTime: playerFinish
            )
            let shortfall = max(0, targetDistance - rivalAtPlayerFinish)
            return ReplayRaceResult(
                outcome: .playerWon,
                axis: .distance,
                timeMargin: absDelta,
                distanceMargin: shortfall,
                rivalDidNotFinish: false,
                playerFinishTime: playerFinish,
                rivalFinishTime: rivalFinish,
                playerDistance: targetDistance,
                rivalDistance: rivalAtPlayerFinish
            )
        } else {
            // Rival faster.
            let playerAtRivalFinish = distanceAtRelativeTime(
                strokes: playerStrokes,
                relativeTime: rivalFinish
            )
            let shortfall = max(0, targetDistance - playerAtRivalFinish)
            return ReplayRaceResult(
                outcome: .rivalWon,
                axis: .distance,
                timeMargin: absDelta,
                distanceMargin: shortfall,
                rivalDidNotFinish: false,
                playerFinishTime: playerFinish,
                rivalFinishTime: rivalFinish,
                playerDistance: playerAtRivalFinish,
                rivalDistance: targetDistance
            )
        }
    }

    // MARK: - Time axis

    private static func timeAxisResult(
        playerStrokes: [Stroke],
        rivalStrokes: [Stroke],
        targetDuration: TimeInterval
    ) -> ReplayRaceResult? {
        guard targetDuration.isFinite, targetDuration > 0 else { return nil }
        guard playerStrokes.count >= 2, rivalStrokes.count >= 2 else { return nil }

        let playerDist = distanceAtRelativeTime(strokes: playerStrokes, relativeTime: targetDuration)
        let rivalDist = distanceAtRelativeTime(strokes: rivalStrokes, relativeTime: targetDuration)
        let delta = playerDist - rivalDist
        let absDelta = abs(delta)

        if absDelta <= timeDistanceTieTolerance {
            return ReplayRaceResult(
                outcome: .tie,
                axis: .time,
                timeMargin: nil,
                distanceMargin: 0,
                rivalDidNotFinish: false,
                playerFinishTime: targetDuration,
                rivalFinishTime: targetDuration,
                playerDistance: playerDist,
                rivalDistance: rivalDist
            )
        }

        if delta > 0 {
            return ReplayRaceResult(
                outcome: .playerWon,
                axis: .time,
                timeMargin: nil,
                distanceMargin: absDelta,
                rivalDidNotFinish: false,
                playerFinishTime: targetDuration,
                rivalFinishTime: targetDuration,
                playerDistance: playerDist,
                rivalDistance: rivalDist
            )
        } else {
            return ReplayRaceResult(
                outcome: .rivalWon,
                axis: .time,
                timeMargin: nil,
                distanceMargin: absDelta,
                rivalDidNotFinish: false,
                playerFinishTime: targetDuration,
                rivalFinishTime: targetDuration,
                playerDistance: playerDist,
                rivalDistance: rivalDist
            )
        }
    }

    // MARK: - Sampling helpers

    /// Distance at relative elapsed time from the first stroke timestamp.
    public static func distanceAtRelativeTime(
        strokes: [Stroke],
        relativeTime: TimeInterval
    ) -> Double {
        guard !strokes.isEmpty else { return 0 }
        let safeElapsed = relativeTime.isFinite ? max(0, relativeTime) : 0
        let absolute = ReplayRaceGap.absoluteTime(elapsed: safeElapsed, strokes: strokes)
        let frame = ReplaySample.sampleAt(strokes: strokes, t: absolute)
        let d = frame.d
        return d.isFinite && d >= 0 ? d : 0
    }
}
