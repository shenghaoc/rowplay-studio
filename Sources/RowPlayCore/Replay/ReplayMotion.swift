import Foundation

/// Shared animation helpers for the 2D replay renderer.
///
/// Everything here is pure and dependency-free so both renderers stay frame-rate
/// independent: phases advance by wall-clock dt, smoothing uses exponential
/// decay, and the particle/governor state machines can be unit-tested without
/// a canvas.
public enum ReplayMotion {
    /// Distance (m) per full stroke/pedal animation cycle, per sport.
    public static func metersPerCycle(for sport: Sport) -> Double {
        switch sport {
        case .rower: 11
        case .skierg: 8
        case .bike: 5
        }
    }

    /// Longest frame delta (s) the animation will integrate. Returning from a
    /// background tab can produce multi-second deltas; clamping keeps phases and
    /// particles from teleporting.
    private static let maxDt: Double = 0.1

    /// Convert a raw frame delta in milliseconds to clamped seconds.
    public static func clampDt(ms: Double) -> Double {
        guard ms.isFinite, ms > 0 else { return 0 }
        return min(ms / 1000, maxDt)
    }

    /// Frame-rate independent smoothing factor for `current += (target - current) * f`.
    /// Equivalent to lerping by `1 - e^(-rate·dt)`: the same `rate` converges at the
    /// same wall-clock speed at 30, 60, or 120 fps.
    public static func dampFactor(rate: Double, dt: Double) -> Double {
        1 - exp(-rate * max(0, dt))
    }

    /// Warp a continuous stroke phase so the drive is quick and the recovery slow,
    /// matching real erg rhythm instead of a symmetric sine. Input and output are
    /// radians with the catch at multiples of 2π; the drive occupies the first
    /// `driveFrac` of each cycle but is remapped onto the first half (0...π) of the
    /// output, so `cos(warped)` swings +1 (catch) → −1 (finish) fast and eases back
    /// through the long recovery.
    public static func warpStrokePhase(_ phase: Double, driveFrac: Double = 0.4) -> Double {
        guard phase.isFinite else { return 0 }
        let tau = Double.pi * 2
        let cycles = floor(phase / tau)
        let u = phase / tau - cycles // 0...1 within the cycle
        let clampedDriveFrac = driveFrac.isFinite ? max(0.01, min(0.99, driveFrac)) : 0.4
        let w: Double = if u < clampedDriveFrac {
            (u / clampedDriveFrac) * 0.5
        } else {
            0.5 + ((u - clampedDriveFrac) / (1 - clampedDriveFrac)) * 0.5
        }
        return (cycles + w) * tau
    }

    /// Hull surge offset for a warped stroke phase: the shell checks (sits back)
    /// at the catch, accelerates through the drive and coasts forward into the
    /// finish. Returns −1...1; callers scale by a per-sport amplitude in their own
    /// units (px or metres).
    public static func strokeSurge(_ warpedPhase: Double) -> Double {
        -cos(warpedPhase)
    }

    /// Count the catches (phase crossing a 2π boundary) between two stroke phases.
    /// Used to trigger splash/spray exactly once per stroke. Jumps larger than
    /// `maxCycles` (seeks) report 0 so a scrub doesn't fire a burst of splashes.
    public static func catchEvents(prev: Double, next: Double, maxCycles: Int = 2) -> Int {
        guard next > prev else { return 0 }
        let tau = Double.pi * 2
        let crossings = Int(floor(next / tau)) - Int(floor(prev / tau))
        guard crossings > 0, next - prev <= Double(maxCycles) * tau else { return 0 }
        return crossings
    }
}
