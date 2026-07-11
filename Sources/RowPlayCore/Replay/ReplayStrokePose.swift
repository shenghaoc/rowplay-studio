import Foundation

/// Aggregates needed to normalize stroke pose intensity/fatigue, mirroring
/// the web `StrokeTimeline` summary fields used by `strokePoseAt()`.
public struct ReplayStrokePoseContext: Equatable, Sendable {
    public let sport: Sport
    public let peakWatts: Int
    public let medianWatts: Int
    /// Median distance per stroke (metres).
    public let medianDPS: Double
    public let maxHR: Int

    public init(
        sport: Sport,
        peakWatts: Int,
        medianWatts: Int,
        medianDPS: Double,
        maxHR: Int
    ) {
        self.sport = sport
        self.peakWatts = peakWatts
        self.medianWatts = medianWatts
        self.medianDPS = medianDPS
        self.maxHR = maxHR
    }
}

/// Per-frame pose state derived from a `ReplayFrame` and sport context.
/// Ported from the web `strokeModel.ts` `StrokePose` interface.
///
/// Every field is a portable numeric value — no RealityKit, SwiftUI, or
/// platform imports. The struct is `Equatable` and `Sendable`.
///
/// Instances should be created via `compute`, `computeAtTime`, or `fallback`.
/// Direct memberwise construction may bypass range invariants enforced by the
/// internal `makePose` factory.
public struct ReplayStrokePose: Equatable, Sendable {
    /// Stroke-row index, used as cycle counter and catch-transition key.
    public var index: Int
    /// Continuous phase in radians; one full cycle per modeled stroke.
    public var phase: Double
    /// Phase warped with an inferred drive/recovery split.
    public var warpedPhase: Double
    /// 0...1 within the current stroke cycle.
    public var cycleFrac: Double
    /// Estimated drive share of the stroke cycle.
    public var driveFrac: Double
    /// Whether the stroke is currently in the drive phase.
    public var drive: Bool
    /// 0...1 progress through the drive phase.
    public var driveProgress: Double
    /// 0...1 progress through the recovery phase.
    public var recoveryProgress: Double
    /// Duration of this stroke in seconds.
    public var strokeSeconds: Double
    /// Distance covered in this stroke in metres.
    public var strokeMeters: Double
    /// Stroke rate (spm or rpm).
    public var rate: Double
    /// Power output in watts.
    public var watts: Int
    /// Normalized intensity 0...1.
    public var intensity: Double
    /// Animation amplitude multiplier (0.72...1.32).
    public var amplitude: Double
    /// Accumulated fatigue 0...1.
    public var fatigue: Double

    // MARK: - Compute

    /// Build a pose from a `ReplayFrame` and context, mirroring the web
    /// `strokePoseAt()` function.
    ///
    /// - Parameters:
    ///   - frame: The interpolated replay frame at the current time.
    ///   - strokeStartDistance: Cumulative distance at the start of this stroke.
    ///   - strokeEndDistance: Cumulative distance at the end of this stroke.
    ///   - strokeStartTime: Time at the start of this stroke.
    ///   - strokeEndTime: Time at the end of this stroke.
    ///   - strokeIndex: Index of the current stroke row.
    ///   - context: Precomputed normalization aggregates.
    ///   - medianHR: Median heart rate across the workout.
    ///   - duration: Total workout duration in seconds.
    public static func compute(
        frame: ReplayFrame,
        strokeStartDistance: Double,
        strokeEndDistance: Double,
        strokeStartTime: TimeInterval,
        strokeEndTime: TimeInterval,
        strokeIndex: Int,
        context: ReplayStrokePoseContext,
        medianHR: Int,
        duration: TimeInterval
    ) -> ReplayStrokePose {
        let sport = context.sport
        let rate = finite(frame.cadence, fallback: defaultRate(for: sport))
        let safeRate = max(0, rate)
        let strokeDuration = max(0.05, strokeEndTime - strokeStartTime)
        let meters = max(0, strokeEndDistance - strokeStartDistance)
        let watts = max(0, frame.watts)

        let (intensity, fatigue) = computeMetrics(
            watts: watts, meters: meters, rate: safeRate, sport: sport,
            context: context, hr: frame.heartRate, medianHR: medianHR,
            progress: frame.progress, duration: duration
        )
        let driveFracVal = driveFraction(sport: sport, seconds: strokeDuration, rate: safeRate, intensity: intensity)

        return makePose(
            sport: sport,
            index: strokeIndex,
            cycleFrac: 0,
            strokeSeconds: strokeDuration,
            strokeMeters: meters,
            rate: safeRate,
            watts: watts,
            intensity: intensity,
            fatigue: fatigue,
            driveFrac: driveFracVal
        )
    }

    /// Compute a pose at an arbitrary time within a stroke, not just at
    /// stroke boundaries. Used by the 3D renderer for smooth animation.
    public static func computeAtTime(
        frame: ReplayFrame,
        strokeStartTime: TimeInterval,
        strokeEndTime: TimeInterval,
        strokeStartDistance: Double,
        strokeEndDistance: Double,
        strokeIndex: Int,
        context: ReplayStrokePoseContext,
        medianHR: Int,
        duration: TimeInterval
    ) -> ReplayStrokePose {
        let sport = context.sport
        let rate = finite(frame.cadence, fallback: defaultRate(for: sport))
        let safeRate = max(0, rate)
        let strokeDuration = max(0.05, strokeEndTime - strokeStartTime)
        let t = finite(frame.t, fallback: strokeStartTime)
        let rawCycleFrac = (t - strokeStartTime) / strokeDuration
        let cycleFrac = clamp(rawCycleFrac, lo: 0, hi: 0.999999)
        let meters = max(0, strokeEndDistance - strokeStartDistance)
        let watts = max(0, frame.watts)

        let (intensity, fatigue) = computeMetrics(
            watts: watts, meters: meters, rate: safeRate, sport: sport,
            context: context, hr: frame.heartRate, medianHR: medianHR,
            progress: frame.progress, duration: duration
        )
        let driveFracVal = driveFraction(sport: sport, seconds: strokeDuration, rate: safeRate, intensity: intensity)

        return makePose(
            sport: sport,
            index: strokeIndex,
            cycleFrac: cycleFrac,
            strokeSeconds: strokeDuration,
            strokeMeters: meters,
            rate: safeRate,
            watts: watts,
            intensity: intensity,
            fatigue: fatigue,
            driveFrac: driveFracVal
        )
    }

    /// Produce a synthetic pose for workouts without stroke data.
    /// Mirrors the web `fallbackStrokePose()`.
    public static func fallback(
        sport: Sport,
        phase: Double = 0,
        rate: Double = 0
    ) -> ReplayStrokePose {
        let safePhase = finite(phase, fallback: 0)
        let safeRate = finite(rate, fallback: defaultRate(for: sport))
        let cycleFrac = (safePhase / tau).truncatingRemainder(dividingBy: 1)
        let safeCycleFrac = cycleFrac < 0 ? cycleFrac + 1 : cycleFrac
        let intensity = clamp(safeRate / (sport == .bike ? 120 : 40), lo: 0, hi: 1)
        let defaultDriveFrac: Double = sport == .bike ? 0.5 : sport == .skierg ? 0.34 : 0.38

        let rawIndex = max(0, safePhase) / tau
        let safeIndex = rawIndex < Double(Int.max - 1) ? Int(rawIndex) : Int.max - 1

        return makePose(
            sport: sport,
            index: safeIndex,
            cycleFrac: safeCycleFrac,
            strokeSeconds: secondsFromRate(safeRate, sport: sport),
            strokeMeters: sport == .bike ? 5 : sport == .skierg ? 8 : 11,
            rate: safeRate,
            watts: 0,
            intensity: intensity,
            fatigue: 0,
            driveFrac: defaultDriveFrac
        )
    }

    /// Freeze a pose for reduced motion: zero out repetitive articulation
    /// while preserving spatial state.
    public static func reducedMotion(_ pose: ReplayStrokePose) -> ReplayStrokePose {
        var frozen = pose
        frozen.phase = 0
        frozen.warpedPhase = 0
        frozen.cycleFrac = 0
        frozen.drive = false
        frozen.driveProgress = 0
        frozen.recoveryProgress = 0
        return frozen
    }
}

// MARK: - Private Helpers

private let tau = Double.pi * 2

private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
    max(lo, min(hi, v))
}

private func defaultRate(for sport: Sport) -> Double {
    switch sport {
    case .bike: 80
    case .skierg: 32
    case .rower: 28
    }
}

/// Convert strokes-per-minute to seconds-per-stroke, clamped to safe ranges
/// per sport (bike: 25–130 rpm, others: 10–60 spm).
private func secondsFromRate(_ spm: Double, sport: Sport) -> Double {
    let base: Double = sport == .bike ? 80 : sport == .skierg ? 32 : 28
    let lo: Double = sport == .bike ? 25 : 10
    let hi: Double = sport == .bike ? 130 : 60
    return 60 / clamp(spm > 0 ? spm : base, lo: lo, hi: hi)
}

/// Estimated drive-to-recovery split for the stroke cycle. Base varies by
/// sport (bike 50%, skierg 34%, rower 38%), adjusted by rate, power, and
/// stroke duration biases. Result clamped to [0.28, 0.46].
private func driveFraction(sport: Sport, seconds: Double, rate: Double, intensity: Double) -> Double {
    if sport == .bike { return 0.5 }
    let base: Double = sport == .skierg ? 0.34 : 0.38
    let rateBase: Double = sport == .skierg ? 32 : 28
    let rateBias = clamp((rate - rateBase) / 40, lo: -0.12, hi: 0.12)
    let powerBias = (intensity - 0.5) * 0.08
    let durationBias = clamp((2.0 - seconds) / 8, lo: -0.06, hi: 0.06)
    return clamp(base + rateBias + powerBias + durationBias, lo: 0.28, hi: 0.46)
}

/// Shared intensity/fatigue computation used by both `compute()` and
/// `computeAtTime()`. Weighted blend: 55% power, 30% distance-per-stroke,
/// 15% cadence. Fatigue: 65% HR-derived, 25% workout progress, 10% penalty
/// for sustained high intensity.
private func computeMetrics(
    watts: Int,
    meters: Double,
    rate: Double,
    sport: Sport,
    context: ReplayStrokePoseContext,
    hr: Int?,
    medianHR: Int,
    progress: Double,
    duration: TimeInterval
) -> (intensity: Double, fatigue: Double) {
    let wattsNorm = context.peakWatts > 0
        ? Double(watts) / Double(context.peakWatts)
        : context.medianWatts > 0
            ? Double(watts) / Double(context.medianWatts)
            : 0.35
    let dpsNorm = context.medianDPS > 0 ? meters / context.medianDPS : 1
    let rateCeiling: Double = sport == .bike ? 120 : 36
    let rateNorm = rate / rateCeiling
    // Weighted blend: 55% power, 30% distance-per-stroke (1.45 divisor prevents
    // outliers from dominating), 15% cadence.
    let intensity = clamp(
        wattsNorm * 0.55 + clamp(dpsNorm / 1.45, lo: 0, hi: 1) * 0.3 + rateNorm * 0.15,
        lo: 0, hi: 1
    )

    let safeHR = hr ?? 0
    // HR-based fatigue: -5 buffer below median before fatigue registers; +10
    // with max(20,...) guard prevents division by a very small range.
    let hrFatigue: Double = safeHR > 0 && context.maxHR > 0
        ? clamp(
            (Double(safeHR) - max(0, Double(medianHR) - 5))
                / max(20, Double(context.maxHR - medianHR) + 10),
            lo: 0, hi: 1
        )
        : 0
    let safeProgress = duration > 0 ? clamp(progress, lo: 0, hi: 1) : 0
    // Weighted: 65% HR-derived fatigue, 25% workout progress, 10% high-intensity penalty.
    let fatigue = clamp(
        hrFatigue * 0.65 + safeProgress * 0.25 + max(0, intensity - 0.75) * 0.1,
        lo: 0, hi: 1
    )
    return (intensity, fatigue)
}

private func makePose(
    sport: Sport,
    index: Int,
    cycleFrac: Double,
    strokeSeconds: Double,
    strokeMeters: Double,
    rate: Double,
    watts: Int,
    intensity: Double,
    fatigue: Double,
    driveFrac: Double
) -> ReplayStrokePose {
    let safeCycleFrac = clamp(cycleFrac, lo: 0, hi: 0.999999)
    let phase = (Double(index) + safeCycleFrac) * tau
    let drive = safeCycleFrac < driveFrac
    let driveProgress = drive ? safeCycleFrac / driveFrac : 1
    let recoveryProgress = drive ? 0 : (safeCycleFrac - driveFrac) / (1 - driveFrac)
    // Base amplitude 0.78, scaled by intensity (×0.44) and fatigue (×0.08),
    // clamped to [0.72, 1.32].
    let amplitude = clamp(0.78 + intensity * 0.44 + fatigue * 0.08, lo: 0.72, hi: 1.32)
    return ReplayStrokePose(
        index: index,
        phase: phase,
        warpedPhase: ReplayMotion.warpStrokePhase(phase, driveFrac: driveFrac),
        cycleFrac: safeCycleFrac,
        driveFrac: driveFrac,
        drive: drive,
        driveProgress: clamp(driveProgress, lo: 0, hi: 1),
        recoveryProgress: clamp(recoveryProgress, lo: 0, hi: 1),
        strokeSeconds: strokeSeconds,
        strokeMeters: strokeMeters,
        rate: rate,
        watts: watts,
        intensity: clamp(intensity, lo: 0, hi: 1),
        amplitude: amplitude,
        fatigue: clamp(fatigue, lo: 0, hi: 1)
    )
}
