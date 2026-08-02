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

public enum WorkoutComparison: Sendable {
    // MARK: - Compare Verdict

    /// Decide which piece was "better" for like-for-like distances (same band),
    /// otherwise compare average pace.
    public static func compareVerdict(_ a: WorkoutDetail, _ b: WorkoutDetail) -> CompareVerdict {
        guard a.workout.sport == b.workout.sport else {
            return CompareVerdict(winner: .tie)
        }

        let axisA = ComparabilityGuard.classifyAxis(workoutType: a.workout.workoutType)
        let axisB = ComparabilityGuard.classifyAxis(workoutType: b.workout.workoutType)
        let likeForLikeDistance = axisA == .distance
            && axisB == .distance
            && WorkoutAnalytics.distanceBand(for: a.workout.distance).key
                == WorkoutAnalytics.distanceBand(for: b.workout.distance).key

        if likeForLikeDistance, a.workout.time > 0, b.workout.time > 0 {
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
        } else if detail.workout.pace > 0 {
            avgWatts = Int(RowPlayFormatting.paceToWatts(
                for: detail.workout.sport,
                pacePer500m: detail.workout.pace
            ).rounded())
        } else {
            avgWatts = 0
        }

        // Best 5-second power: sliding window over strokes
        let best5sPower = computeBest5sPower(strokes: strokes)

        // HR stats
        let hrStats = computeHrStats(strokes: strokes, fallbackAvg: detail.workout.heartRateAvg)

        // DPS (distance per stroke)
        let avgDps = computeAvgDps(strokes: strokes)

        // Pace consistency (coefficient of variation)
        let paceConsistency = computePaceConsistency(strokes: strokes, splits: detail.splits)

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
        guard steps > 0 else { return nil }
        guard let endA = strokesA.last?.d, endA > 0,
              let endB = strokesB.last?.d, endB > 0 else { return nil }
        let alignedMetres = min(endA, endB)
        guard alignedMetres > 0 else { return nil }

        var xs: [Double] = []
        var paceA: [Double?] = []
        var paceB: [Double?] = []
        var powerA: [Double?] = []
        var powerB: [Double?] = []
        var hrA: [Double?] = []
        var hrB: [Double?] = []

        for i in 0...steps {
            let d = alignedMetres * Double(i) / Double(steps)
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
            alignedMetres: alignedMetres
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
            split.isRest != true && split.time >= 30
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
        guard strokes.count >= 2 else { return 0 }
        let total = strokes[strokes.count - 1].t
        guard total >= 5 else { return 0 }

        var energy = Array(repeating: 0.0, count: strokes.count)
        var previous = strokes[0]
        for index in 1..<strokes.count {
            let current = strokes[index]
            energy[index] = energy[index - 1]
                + ((Double(current.watts + previous.watts) / 2) * (current.t - previous.t))
            previous = current
        }

        let duration = 5.0
        var best = 0.0
        var windowEnd = 0

        for windowStart in 0..<strokes.count {
            let startTime = strokes[windowStart].t
            let endTime = startTime + duration
            if endTime > total { break }

            while windowEnd < strokes.count - 1, strokes[windowEnd + 1].t <= endTime {
                windowEnd += 1
            }

            let energyAtEnd: Double
            if windowEnd == strokes.count - 1 {
                energyAtEnd = energy[windowEnd]
            } else {
                let span = strokes[windowEnd + 1].t - strokes[windowEnd].t
                let fraction = span == 0 ? 0 : (endTime - strokes[windowEnd].t) / span
                energyAtEnd = energy[windowEnd] + (energy[windowEnd + 1] - energy[windowEnd]) * fraction
            }

            let avg = (energyAtEnd - energy[windowStart]) / duration
            if avg > best { best = avg }
        }

        return Int(best.rounded())
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

        let computedAvg = count > 0 ? Int((Double(sum) / Double(count)).rounded()) : nil
        let avg = (fallbackAvg != nil && fallbackAvg! > 0) ? fallbackAvg : computedAvg
        let finalPeak = count > 0 ? peak : nil
        return (avg, finalPeak)
    }

    /// Average distance per stroke.
    private static func computeAvgDps(strokes: [Stroke]) -> Double {
        var sum = 0.0
        var count = 0
        for stroke in strokes {
            if let dps = ReplayInspector.distancePerStroke(pace: stroke.pace, cadence: stroke.cadence) {
                sum += dps
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// Pace coefficient of variation (%).
    /// Prefers stroke paces when at least two positive samples exist; otherwise falls back to non-rest splits.
    /// Computed without intermediate pace arrays (two O(N) passes, O(1) auxiliary space).
    private static func computePaceConsistency(strokes: [Stroke], splits: [Split]) -> Double {
        if let strokeCV = coefficientOfVariation(
            count: strokes.count,
            valueAt: { strokes[$0].pace },
            include: { strokes[$0].pace > 0 }
        ) {
            return strokeCV
        }

        return coefficientOfVariation(
            count: splits.count,
            valueAt: { splits[$0].pace },
            include: { splits[$0].isRest != true && splits[$0].pace > 0 }
        ) ?? 0
    }

    /// Population coefficient of variation (%). Returns `nil` when fewer than two samples match `include`.
    private static func coefficientOfVariation(
        count: Int,
        valueAt: (Int) -> Double,
        include: (Int) -> Bool
    ) -> Double? {
        var sampleCount = 0
        var sum = 0.0
        for index in 0..<count where include(index) {
            sum += valueAt(index)
            sampleCount += 1
        }
        guard sampleCount >= 2 else { return nil }

        let mean = sum / Double(sampleCount)
        guard mean > 0 else { return 0 }

        var sumSquaredDeviation = 0.0
        for index in 0..<count where include(index) {
            let delta = valueAt(index) - mean
            sumSquaredDeviation += delta * delta
        }
        let stddev = sqrt(sumSquaredDeviation / Double(sampleCount))
        return (stddev / mean) * 100
    }
}
