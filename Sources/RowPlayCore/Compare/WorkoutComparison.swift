import Foundation

/// Which workout "won" a comparison.
public enum CompareWinner: String, Sendable {
    case a
    case b
    case tie
}

/// Result of comparing two workouts.
public struct CompareVerdict: Equatable, Sendable {
    public var winner: CompareWinner
    /// Seconds faster for workout A when distances are comparable (positive = A faster).
    public var timeDeltaSec: Double?
    /// Pace delta (A − B) in sec/500m; negative = A is faster.
    public var paceDelta: Double?

    public init(winner: CompareWinner, timeDeltaSec: Double? = nil, paceDelta: Double? = nil) {
        self.winner = winner
        self.timeDeltaSec = timeDeltaSec
        self.paceDelta = paceDelta
    }
}

/// Per-workout statistics for the compare view.
public struct WorkoutSideStats: Equatable, Sendable {
    public var time: TimeInterval
    public var pace: TimeInterval
    public var avgWatts: Int
    public var best5sPower: Int
    public var avgHr: Int?
    public var peakHr: Int?
    public var avgDps: Double
    /// Pace coefficient of variation (%); lower = more even splits.
    public var paceConsistency: Double

    public init(
        time: TimeInterval,
        pace: TimeInterval,
        avgWatts: Int,
        best5sPower: Int,
        avgHr: Int? = nil,
        peakHr: Int? = nil,
        avgDps: Double,
        paceConsistency: Double
    ) {
        self.time = time
        self.pace = pace
        self.avgWatts = avgWatts
        self.best5sPower = best5sPower
        self.avgHr = avgHr
        self.peakHr = peakHr
        self.avgDps = avgDps
        self.paceConsistency = paceConsistency
    }
}

/// Per-rep comparison row for interval workouts.
public struct IntervalCompareRow: Equatable, Sendable {
    public var index: Int
    public var paceA: TimeInterval
    public var paceB: TimeInterval
    /// A pace − B pace (sec/500m); negative = A faster on this rep.
    public var paceDelta: Double
    public var timeA: TimeInterval
    public var timeB: TimeInterval
    /// B time − A time (sec); positive = A faster.
    public var timeDelta: Double

    public init(
        index: Int,
        paceA: TimeInterval,
        paceB: TimeInterval,
        paceDelta: Double,
        timeA: TimeInterval,
        timeB: TimeInterval,
        timeDelta: Double
    ) {
        self.index = index
        self.paceA = paceA
        self.paceB = paceB
        self.paceDelta = paceDelta
        self.timeA = timeA
        self.timeB = timeB
        self.timeDelta = timeDelta
    }
}

/// Resampled overlay data for two workouts on a shared distance grid.
public struct DistanceOverlay: Equatable, Sendable {
    public var xs: [Double]
    public var paceA: [Double?]
    public var paceB: [Double?]
    public var powerA: [Double?]
    public var powerB: [Double?]
    public var hrA: [Double?]
    public var hrB: [Double?]
    public var alignedMetres: Double

    public init(
        xs: [Double],
        paceA: [Double?],
        paceB: [Double?],
        powerA: [Double?],
        powerB: [Double?],
        hrA: [Double?],
        hrB: [Double?],
        alignedMetres: Double
    ) {
        self.xs = xs
        self.paceA = paceA
        self.paceB = paceB
        self.powerA = powerA
        self.powerB = powerB
        self.hrA = hrA
        self.hrB = hrB
        self.alignedMetres = alignedMetres
    }
}

public enum WorkoutComparison {
    // MARK: - Compare Verdict

    /// Decide which piece was "better" for like-for-like distances (same band),
    /// otherwise compare average pace.
    public static func compareVerdict(_ a: WorkoutDetail, _ b: WorkoutDetail) -> CompareVerdict {
        guard a.workout.sport == b.workout.sport else {
            return CompareVerdict(winner: .tie)
        }

        let bandA = WorkoutAnalytics.distanceBand(for: a.workout.distance)
        let bandB = WorkoutAnalytics.distanceBand(for: b.workout.distance)
        let likeForLike = bandA.key == bandB.key

        if likeForLike, a.workout.time > 0, b.workout.time > 0 {
            let timeDeltaSec = b.workout.time - a.workout.time // positive = A faster
            var winner: CompareWinner = .tie
            if abs(timeDeltaSec) >= 0.5 { winner = timeDeltaSec > 0 ? .a : .b }
            return CompareVerdict(
                winner: winner,
                timeDeltaSec: timeDeltaSec,
                paceDelta: a.workout.pace - b.workout.pace
            )
        }

        let paceDelta = a.workout.pace - b.workout.pace
        var winner: CompareWinner = .tie
        if a.workout.pace > 0, b.workout.pace > 0, abs(paceDelta) >= 0.1 {
            winner = paceDelta < 0 ? .a : .b
        }
        return CompareVerdict(winner: winner, paceDelta: paceDelta)
    }

    // MARK: - Side Stats

    /// Compute per-workout statistics from strokes and splits.
    public static func sideStats(_ detail: WorkoutDetail) -> WorkoutSideStats {
        let strokes = detail.strokes

        // Average watts from total watt-minutes or pace fallback
        let avgWatts: Int
        if let wattMinutes = detail.workout.wattMinutes, detail.workout.time > 0 {
            avgWatts = Int((wattMinutes * 60 / detail.workout.time).rounded())
        } else {
            avgWatts = Int(RowPlayFormatting.paceToWatts(detail.workout.pace).rounded())
        }

        // Best 5-second power: sliding window over strokes
        let best5sPower = computeBest5sPower(strokes: strokes)

        // HR stats
        let hrStats = computeHrStats(strokes: strokes, fallbackAvg: detail.workout.heartRateAvg)

        // DPS (distance per stroke)
        let avgDps = computeAvgDps(strokes: strokes, totalDistance: detail.workout.distance)

        // Pace consistency (coefficient of variation)
        let paceConsistency = computePaceConsistency(strokes: strokes)

        return WorkoutSideStats(
            time: detail.workout.time,
            pace: detail.workout.pace,
            avgWatts: avgWatts,
            best5sPower: best5sPower,
            avgHr: hrStats.avg,
            peakHr: hrStats.peak,
            avgDps: avgDps,
            paceConsistency: paceConsistency
        )
    }

    // MARK: - Interval Compare

    /// Per-rep deltas when both workouts have interval splits.
    public static func compareIntervalReps(
        _ a: WorkoutDetail,
        _ b: WorkoutDetail
    ) -> [IntervalCompareRow]? {
        guard a.workout.sport == b.workout.sport else { return nil }
        guard let setA = intervalReps(from: a),
              let setB = intervalReps(from: b) else { return nil }
        let n = min(setA.count, setB.count)
        guard n >= 2 else { return nil }

        return (0..<n).map { i in
            let ra = setA[i]
            let rb = setB[i]
            return IntervalCompareRow(
                index: i + 1,
                paceA: ra.pace,
                paceB: rb.pace,
                paceDelta: ra.pace - rb.pace,
                timeA: ra.time,
                timeB: rb.time,
                timeDelta: rb.time - ra.time
            )
        }
    }

    // MARK: - Distance Overlay

    /// Resample two stroke streams onto a shared distance grid for chart overlay.
    public static func buildDistanceOverlay(
        _ strokesA: [Stroke],
        _ strokesB: [Stroke],
        steps: Int = 120
    ) -> DistanceOverlay? {
        guard let endA = strokesA.last?.d, endA > 0,
              let endB = strokesB.last?.d, endB > 0 else { return nil }
        let aligned = min(endA, endB)
        guard aligned > 0 else { return nil }

        var xs: [Double] = []
        var paceA: [Double?] = []
        var paceB: [Double?] = []
        var powerA: [Double?] = []
        var powerB: [Double?] = []
        var hrA: [Double?] = []
        var hrB: [Double?] = []

        for i in 0...steps {
            let d = aligned * Double(i) / Double(steps)
            xs.append(d)
            let sa = sampleStrokeAtDistance(strokesA, d)
            let sb = sampleStrokeAtDistance(strokesB, d)
            paceA.append(sa.flatMap { $0.pace > 0 ? $0.pace : nil })
            paceB.append(sb.flatMap { $0.pace > 0 ? $0.pace : nil })
            powerA.append(sa.flatMap { $0.watts > 0 ? Double($0.watts) : nil })
            powerB.append(sb.flatMap { $0.watts > 0 ? Double($0.watts) : nil })
            hrA.append(sa.flatMap { $0.heartRate.map { Double($0) } })
            hrB.append(sb.flatMap { $0.heartRate.map { Double($0) } })
        }

        return DistanceOverlay(
            xs: xs, paceA: paceA, paceB: paceB,
            powerA: powerA, powerB: powerB,
            hrA: hrA, hrB: hrB,
            alignedMetres: aligned
        )
    }

    // MARK: - Private Helpers

    private struct IntervalRep {
        var pace: TimeInterval
        var time: TimeInterval
    }

    /// Extract work interval reps from a detail (non-rest splits with >= 30s).
    private static func intervalReps(from detail: WorkoutDetail) -> [IntervalRep]? {
        guard detail.workout.isInterval else { return nil }
        let workSplits = detail.splits.filter { split in
            // A work split is non-rest with >= 30 seconds
            split.time >= 30
        }
        guard workSplits.count >= 2 else { return nil }
        return workSplits.map { IntervalRep(pace: $0.pace, time: $0.time) }
    }

    /// Linear interpolation of stroke data at a given distance.
    private static func sampleStrokeAtDistance(_ strokes: [Stroke], _ d: Double) -> Stroke? {
        guard !strokes.isEmpty else { return nil }
        if d <= strokes[0].d { return strokes[0] }
        if d >= strokes[strokes.count - 1].d { return strokes[strokes.count - 1] }

        // Binary search for the bracket
        var lo = 0
        var hi = strokes.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if strokes[mid].d <= d { lo = mid } else { hi = mid }
        }

        let s0 = strokes[lo]
        let s1 = strokes[hi]
        let dRange = s1.d - s0.d
        guard dRange > 0 else { return s0 }

        let frac = (d - s0.d) / dRange
        let t = s0.t + (s1.t - s0.t) * frac
        let pace = s0.pace + (s1.pace - s0.pace) * frac
        let cadence = s0.cadence + (s1.cadence - s0.cadence) * frac
        let watts = Int((Double(s0.watts) + Double(s1.watts - s0.watts) * frac).rounded())
        let hr: Int?
        if let hr0 = s0.heartRate, let hr1 = s1.heartRate {
            hr = Int((Double(hr0) + Double(hr1 - hr0) * frac).rounded())
        } else {
            hr = s0.heartRate ?? s1.heartRate
        }

        return Stroke(t: t, d: d, pace: pace, cadence: cadence, heartRate: hr, watts: watts)
    }

    /// Best 5-second average power from strokes.
    private static func computeBest5sPower(strokes: [Stroke]) -> Int {
        guard strokes.count >= 2 else {
            return strokes.first.map { $0.watts } ?? 0
        }

        var best = 0
        var windowStart = 0

        for windowEnd in 0..<strokes.count {
            // Shrink window to fit within 5 seconds
            while windowEnd > windowStart,
                  strokes[windowEnd].t - strokes[windowStart].t > 5.0 {
                windowStart += 1
            }
            // Compute average power in window
            let count = windowEnd - windowStart + 1
            guard count > 0 else { continue }
            let sum = strokes[windowStart...windowEnd].reduce(0) { $0 + $1.watts }
            let avg = sum / count
            if avg > best { best = avg }
        }

        return best
    }

    /// Compute HR statistics from strokes.
    private static func computeHrStats(strokes: [Stroke], fallbackAvg: Int?) -> (avg: Int?, peak: Int?) {
        var sum = 0
        var count = 0
        var peak = 0

        for s in strokes {
            if let hr = s.heartRate, hr > 0 {
                sum += hr
                count += 1
                if hr > peak { peak = hr }
            }
        }

        let computedAvg = count > 0 ? sum / count : nil
        let avg = (fallbackAvg != nil && fallbackAvg! > 0) ? fallbackAvg : computedAvg
        let finalPeak = count > 0 ? peak : nil
        return (avg, finalPeak)
    }

    /// Average distance per stroke.
    private static func computeAvgDps(strokes: [Stroke], totalDistance: Double) -> Double {
        guard let lastStroke = strokes.last, lastStroke.d > 0 else { return 0 }
        let strokeCount = strokes.count
        guard strokeCount > 0 else { return 0 }
        return lastStroke.d / Double(strokeCount)
    }

    /// Pace coefficient of variation (%).
    private static func computePaceConsistency(strokes: [Stroke]) -> Double {
        let paces = strokes.map { $0.pace }.filter { $0 > 0 }
        guard paces.count >= 2 else { return 0 }

        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return 0 }

        let variance = paces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(paces.count)
        let stddev = sqrt(variance)
        return (stddev / mean) * 100
    }
}
