import Foundation

/// A single interpolated frame of workout state at a point in time.
public struct ReplayFrame: Equatable, Sendable {
    public var t: TimeInterval
    public var d: Double
    public var pace: TimeInterval
    public var cadence: Double
    public var heartRate: Int?
    public var watts: Int
    /// Fraction of the workout completed, 0...1 (by time).
    public var progress: Double

    public init(
        t: TimeInterval,
        d: Double,
        pace: TimeInterval,
        cadence: Double,
        heartRate: Int? = nil,
        watts: Int,
        progress: Double
    ) {
        self.t = t
        self.d = d
        self.pace = pace
        self.cadence = cadence
        self.heartRate = heartRate
        self.watts = watts
        self.progress = progress
    }
}

public enum ReplaySample {
    /// Linearly interpolate the workout state at time `t` (seconds).
    ///
    /// Pure and stateless so it can be reused for a "ghost" track: just call
    /// `sampleAt(ghostStrokes, t)` alongside the live one and render both.
    public static func sampleAt(strokes: [Stroke], t: TimeInterval) -> ReplayFrame {
        let n = strokes.count
        if n == 0 || !t.isFinite {
            return ReplayFrame(t: t, d: 0, pace: 0, cadence: 0, watts: 0, progress: 0)
        }
        let total = strokes[n - 1].t > 0 ? strokes[n - 1].t : 1
        let progress = max(0, min(1, t / total))

        if t <= strokes[0].t {
            return frameFrom(strokes[0], t: t, progress: progress)
        }
        if t >= strokes[n - 1].t {
            return frameFrom(strokes[n - 1], t: t, progress: progress)
        }

        // Binary search for the bracketing samples.
        var lo = 0
        var hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if strokes[mid].t <= t {
                lo = mid
            } else {
                hi = mid
            }
        }
        let a = strokes[lo]
        let b = strokes[hi]
        let span = b.t - a.t > 0 ? b.t - a.t : 1
        let f = (t - a.t) / span

        return ReplayFrame(
            t: t,
            d: lerp(a.d, b.d, f),
            pace: lerp(a.pace, b.pace, f),
            cadence: lerp(a.cadence, b.cadence, f),
            heartRate: lerpOptionalInt(a.heartRate, b.heartRate, f),
            watts: Int(lerp(Double(a.watts), Double(b.watts), f).rounded()),
            progress: progress
        )
    }

    /// Index of the most recent stroke at or before `t` (sample-and-hold).
    /// Mirrors `sampleAt`'s bracketing search but returns the lower index.
    public static func sampleIndexAt(strokes: [Stroke], t: TimeInterval) -> Int {
        let n = strokes.count
        if n == 0 { return -1 }
        if t <= strokes[0].t { return 0 }
        if t >= strokes[n - 1].t { return n - 1 }

        var lo = 0
        var hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if strokes[mid].t <= t {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo
    }

    // MARK: - Private

    private static func frameFrom(_ s: Stroke, t: TimeInterval, progress: Double) -> ReplayFrame {
        ReplayFrame(
            t: t,
            d: s.d,
            pace: s.pace,
            cadence: s.cadence,
            heartRate: s.heartRate,
            watts: s.watts,
            progress: progress
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double {
        a + (b - a) * f
    }

    private static func lerpOptionalInt(_ a: Int?, _ b: Int?, _ f: Double) -> Int? {
        if let a, let b {
            return Int((Double(a) + (Double(b) - Double(a)) * f).rounded())
        }
        return a ?? b
    }
}
