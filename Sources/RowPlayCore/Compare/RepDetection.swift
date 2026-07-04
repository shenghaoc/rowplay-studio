import Foundation

/// A time series for one detected rep/interval.
public struct RepSeries: Equatable, Sendable {
    public var repIndex: Int
    public var avgPace: TimeInterval
    public var times: [Double]
    public var pace: [Double]
    public var rate: [Double]
    public var power: [Double]
    public var hr: [Double]

    public init(
        repIndex: Int,
        avgPace: TimeInterval,
        times: [Double],
        pace: [Double],
        rate: [Double],
        power: [Double],
        hr: [Double]
    ) {
        self.repIndex = repIndex
        self.avgPace = avgPace
        self.times = times
        self.pace = pace
        self.rate = rate
        self.power = power
        self.hr = hr
    }
}

public enum RepDetection {
    private static let minRepSeconds: TimeInterval = 30
    private static let minReps = 2

    /// Returns one RepSeries per work interval, or nil when the workout is not
    /// a recognisable multi-rep piece (< 2 work intervals or each < 30 s).
    public static func detectReps(_ detail: WorkoutDetail) -> [RepSeries]? {
        guard detail.workout.isInterval else { return nil }
        let work = workSplits(detail.splits)
        guard work.count >= minReps else { return nil }

        let buckets = assignStrokesToWorkReps(splits: detail.splits, strokes: detail.strokes)
        var repIndex = 0
        var series: [RepSeries] = []

        for split in detail.splits {
            // Skip rest or short splits
            guard split.isRest != true, split.time >= minRepSeconds else { continue }

            let bucket = repIndex < buckets.count ? buckets[repIndex] : []
            let base: (times: [Double], pace: [Double], rate: [Double], power: [Double], hr: [Double])
            if !bucket.isEmpty {
                base = seriesFromStrokes(bucket)
            } else {
                base = seriesFromSplit(split, sport: detail.workout.sport)
            }
            let avgPace = repAvgPaceFromArrays(base.pace, fallback: split.pace)
            series.append(RepSeries(
                repIndex: repIndex,
                avgPace: avgPace,
                times: base.times,
                pace: base.pace,
                rate: base.rate,
                power: base.power,
                hr: base.hr
            ))
            repIndex += 1
        }

        return series.count >= minReps ? series : nil
    }

    /// Average pace for a rep series.
    public static func repAvgPace(_ series: RepSeries) -> TimeInterval {
        series.avgPace
    }

    /// True when any rep carries HR data.
    public static func repsHaveHr(_ reps: [RepSeries]) -> Bool {
        reps.contains { rep in rep.hr.contains { $0 > 0 } }
    }

    // MARK: - Private Helpers

    private static func workSplits(_ splits: [Split]) -> [Split] {
        splits.filter { $0.isRest != true && $0.time >= minRepSeconds }
    }

    /// Assign strokes to work rep buckets based on split time boundaries.
    private static func assignStrokesToWorkReps(splits: [Split], strokes: [Stroke]) -> [[Stroke]] {
        let workCount = workSplits(splits).count
        var buckets: [[Stroke]] = Array(repeating: [], count: workCount)
        guard !strokes.isEmpty, workCount > 0 else { return buckets }

        // Build cumulative time edges
        var edges: [Double] = []
        var cum: Double = 0
        for split in splits {
            cum += split.time
            edges.append(cum)
        }

        // Map each split index to a work-rep bucket (or -1 for short splits)
        var splitToWork: [Int] = []
        var workIdx = 0
        for split in splits {
            if split.isRest != true && split.time >= minRepSeconds {
                splitToWork.append(workIdx)
                workIdx += 1
            } else {
                splitToWork.append(-1)
            }
        }

        var e = 0
        for s in strokes.sorted(by: { $0.t < $1.t }) {
            while e < edges.count, s.t > edges[e] { e += 1 }
            let idx = e < splitToWork.count ? splitToWork[e] : -1
            if idx >= 0 { buckets[idx].append(s) }
        }

        return buckets
    }

    private static func seriesFromStrokes(_ strokes: [Stroke]) -> (times: [Double], pace: [Double], rate: [Double], power: [Double], hr: [Double]) {
        guard let t0 = strokes.first?.t else {
            return ([], [], [], [], [])
        }
        let times = strokes.map { $0.t - t0 }
        let pace = strokes.map { $0.pace }
        let rate = strokes.map { $0.cadence }
        let power = strokes.map { Double($0.watts) }
        let hr = strokes.map { $0.heartRate.map { Double($0) } ?? 0 }
        return (times, pace, rate, power, hr)
    }

    private static func seriesFromSplit(_ split: Split, sport: Sport) -> (times: [Double], pace: [Double], rate: [Double], power: [Double], hr: [Double]) {
        let steps = max(1, Int(split.time.rounded()))
        let spm = split.cadence ?? 0
        let hrVal = split.heartRate?.average.map { Double($0) } ?? 0
        let watts = split.pace > 0
            ? RowPlayFormatting.paceToWatts(for: sport, pacePer500m: split.pace)
            : 0

        let times = (0..<steps).map { Double($0) }
        let pace = Array(repeating: split.pace, count: steps)
        let rate = Array(repeating: spm, count: steps)
        let power = Array(repeating: watts, count: steps)
        let hr = Array(repeating: hrVal, count: steps)
        return (times, pace, rate, power, hr)
    }

    private static func repAvgPaceFromArrays(_ pace: [Double], fallback: TimeInterval) -> TimeInterval {
        let valid = pace.filter { $0 > 0 }
        if !valid.isEmpty {
            return valid.reduce(0, +) / Double(valid.count)
        }
        return fallback > 0 ? fallback : 0
    }
}
