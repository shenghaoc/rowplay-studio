import Foundation

/// One heart-rate sample on the import file's elapsed-time axis (seconds).
public struct HrSample: Equatable, Sendable {
    public var t: TimeInterval
    public var hr: Int

    public init(t: TimeInterval, hr: Int) {
        self.t = t
        self.hr = hr
    }
}

public enum HrImport {
    private static let minSamples = 2

    /// Extract valid HR samples from strokes.
    public static func extractHrSeries(_ strokes: [Stroke]) -> [HrSample] {
        strokes
            .filter { $0.heartRate != nil && $0.heartRate! > 0 && $0.t.isFinite }
            .map { HrSample(t: $0.t, hr: $0.heartRate!) }
            .sorted { $0.t < $1.t }
    }

    /// Linear HR interpolation at `fileTime`; nil outside range.
    public static func interpolateHr(_ samples: [HrSample], at fileTime: TimeInterval) -> Int? {
        guard !samples.isEmpty, fileTime.isFinite else { return nil }
        if fileTime < samples[0].t || fileTime > samples[samples.count - 1].t { return nil }
        if fileTime == samples[0].t { return samples[0].hr }

        var lo = 0
        var hi = samples.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= fileTime { lo = mid } else { hi = mid }
        }
        let a = samples[lo]
        let b = samples[hi]
        if a.t == b.t { return a.hr }
        let frac = (fileTime - a.t) / (b.t - a.t)
        return Int((Double(a.hr) + Double(b.hr - a.hr) * frac).rounded())
    }

    /// Merge external HR samples into workout strokes.
    public static func mergeHrIntoStrokes(
        _ strokes: [Stroke],
        samples: [HrSample],
        offsetSec: TimeInterval
    ) -> [Stroke] {
        guard !samples.isEmpty else { return strokes }
        return strokes.map { s in
            guard let hr = interpolateHr(samples, at: s.t + offsetSec) else { return s }
            return Stroke(t: s.t, d: s.d, pace: s.pace, cadence: s.cadence, heartRate: hr, watts: s.watts)
        }
    }

    /// Compute avg/min/max HR from strokes.
    public static func summarizeHr(_ strokes: [Stroke]) -> (avg: Int?, min: Int?, max: Int?) {
        var sum = 0
        var count = 0
        var minHr = Int.max
        var maxHr = Int.min

        for s in strokes {
            if let hr = s.heartRate, hr > 0 {
                sum += hr
                count += 1
                if hr < minHr { minHr = hr }
                if hr > maxHr { maxHr = hr }
            }
        }

        guard count > 0 else { return (nil, nil, nil) }
        return (Int((Double(sum) / Double(count)).rounded()), minHr, maxHr)
    }

    /// True when any stroke carries HR data.
    public static func strokesHaveHr(_ strokes: [Stroke]) -> Bool {
        strokes.contains { $0.heartRate != nil && $0.heartRate! > 0 }
    }

    /// Produce a new WorkoutDetail with merged HR across strokes and splits.
    public static func applyHrImport(
        _ detail: WorkoutDetail,
        samples: [HrSample],
        offsetSec: TimeInterval
    ) -> WorkoutDetail {
        let mergedStrokes = mergeHrIntoStrokes(detail.strokes, samples: samples, offsetSec: offsetSec)
        let hrStats = summarizeHr(mergedStrokes)

        // Update splits with average HR per split
        var cumulativeDistance: Double = 0
        var strokeIdx = 0
        let mergedSplits = detail.splits.map { split -> Split in
            let startD = cumulativeDistance
            cumulativeDistance += split.distance
            let endD = cumulativeDistance

            var sumHr = 0
            var countHr = 0

            // Advance strokeIdx to start of this split
            while strokeIdx < mergedStrokes.count, mergedStrokes[strokeIdx].d <= startD {
                strokeIdx += 1
            }

            // Process strokes within this split
            var j = strokeIdx
            while j < mergedStrokes.count, mergedStrokes[j].d <= endD {
                if let hr = mergedStrokes[j].heartRate, hr > 0 {
                    sumHr += hr
                    countHr += 1
                }
                j += 1
            }

            guard countHr > 0 else { return split }
            let avgHr = Int((Double(sumHr) / Double(countHr)).rounded())
            var updated = split
            updated.heartRate = HeartRateDetail(average: avgHr)
            return updated
        }

        var updatedWorkout = detail.workout
        updatedWorkout.heartRateAvg = hrStats.avg

        return WorkoutDetail(
            workout: updatedWorkout,
            strokes: mergedStrokes,
            splits: mergedSplits
        )
    }
}
