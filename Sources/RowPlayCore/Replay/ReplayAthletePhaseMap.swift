import Foundation

/// Native replay clock values consumed by the production-athlete clip map.
public struct ReplayAthleteMotionSample: Equatable, Sendable {
    public let phase: Double
    public let cycleFrac: Double
    public let driveFrac: Double

    public init(phase: Double, cycleFrac: Double, driveFrac: Double) {
        self.phase = phase
        self.cycleFrac = cycleFrac
        self.driveFrac = driveFrac
    }

    public init(strokePose: ReplayStrokePose) {
        self.phase = strokePose.phase
        self.cycleFrac = strokePose.cycleFrac
        self.driveFrac = strokePose.driveFrac
    }
}

/// Pure phase-to-authored-clip mapping shared by every renderer.
///
/// The native drive share (`ReplayStrokePose.driveFrac`, 0.28...0.46 for
/// RowErg and SkiErg) rarely equals the authored clip's `driveEnd` (0.38
/// rower, 0.34 SkiErg, 0.50 bike), so one native cycle has to be re-timed onto
/// the authored one.  A two-segment linear map does that but is only C0: its
/// playback speed steps by up to 65% at the drive/recovery seam and again at
/// the cycle wrap, landing exactly on the finish and the catch.  This uses a
/// monotone cubic Hermite instead, so speed is continuous everywhere on the
/// cycle.
public enum ReplayAthletePhaseMap {
    /// Lowest and highest drive share either the native clock or an authored
    /// clip may claim.  Both ends stay away from 0 and 1 so every secant slope
    /// below is finite and strictly positive.
    static let minimumDriveShare = 0.05
    static let maximumDriveShare = 0.95
    /// Drive share assumed when the native clock reports a non-finite one.
    static let fallbackSourceDrive = 0.4
    /// Authored drive end assumed when a clip reports a non-finite one.
    static let fallbackClipDrive = 0.5

    /// Map one native stroke cycle onto the authored clip's drive/recovery
    /// split without introducing an independent animation clock.
    ///
    /// The map interpolates the three cycle landmarks the renderer must hit
    /// exactly — `f(0) = 0`, `f(sourceDrive) = clipDrive`, `f(1) = 1` — with a
    /// pair of cubic Hermite segments sharing one tangent.
    ///
    /// The shared tangent is the PCHIP (Fritsch–Butland) weighted harmonic
    /// mean of the two secant slopes.  Evaluating that formula at the interior
    /// knot and at the wrap knot yields the *same* value for a two-segment
    /// cycle, so a single tangent makes the map C1 at the drive/recovery seam
    /// **and** across the cycle wrap.  See
    /// `.kiro/specs/phase-13-replay-motion-expressiveness/design.md`.
    public static func clipFraction(
        sample: ReplayAthleteMotionSample,
        authoredDriveEnd: Double
    ) -> Double {
        let phaseCycle = ReplayAthleteMotionTable.wrapUnit(sample.phase / (2 * Double.pi))
        let cycle = sample.cycleFrac.isFinite
            ? ReplayAthleteMotionTable.wrapUnit(sample.cycleFrac)
            : phaseCycle
        let sourceDrive = clampedDriveShare(sample.driveFrac, fallback: fallbackSourceDrive)
        let clipDrive = clampedDriveShare(authoredDriveEnd, fallback: fallbackClipDrive)

        // Secants of the two landmark segments. Both are finite and strictly
        // positive because each drive share is clamped inside (0, 1).
        let driveSecant = clipDrive / sourceDrive
        let recoverySecant = (1 - clipDrive) / (1 - sourceDrive)
        let tangent = sharedTangent(
            sourceDrive: sourceDrive,
            driveSecant: driveSecant,
            recoverySecant: recoverySecant
        )
        guard tangent.isFinite, tangent > 0 else {
            // Unreachable for clamped inputs; the linear map stays the
            // fallback rather than emitting a non-finite clip fraction.
            return cycle < sourceDrive
                ? (cycle / sourceDrive) * clipDrive
                : clipDrive + ((cycle - sourceDrive) / (1 - sourceDrive)) * (1 - clipDrive)
        }

        let mapped: Double
        if cycle < sourceDrive {
            mapped = hermite(
                start: 0,
                span: sourceDrive,
                startValue: 0,
                secant: driveSecant,
                tangent: tangent,
                cycle: cycle
            )
        } else {
            mapped = hermite(
                start: sourceDrive,
                span: 1 - sourceDrive,
                startValue: clipDrive,
                secant: recoverySecant,
                tangent: tangent,
                cycle: cycle
            )
        }
        guard mapped.isFinite else { return clipDrive }
        return min(1, max(0, mapped))
    }

    public static func isDrive(clipFraction: Double, authoredDriveEnd: Double) -> Bool {
        // Compared against the same clamped drive end `clipFraction` maps
        // onto, so `isDrive(clipFraction(c)) == (c < sourceDrive)` holds for
        // every input the map accepts, including non-finite authored values.
        ReplayAthleteMotionTable.wrapUnit(clipFraction)
            < clampedDriveShare(authoredDriveEnd, fallback: fallbackClipDrive)
    }

    static func clampedDriveShare(_ value: Double, fallback: Double) -> Double {
        min(maximumDriveShare, max(minimumDriveShare, value.isFinite ? value : fallback))
    }

    /// PCHIP weighted harmonic mean of the two secants.
    ///
    /// With `h` the left interval and `1 - h` the right, the Fritsch–Butland
    /// weights are `w₁ = 2(1-h) + h` against the left secant and
    /// `w₂ = (1-h) + 2h` against the right, and `w₁ + w₂ = 3`.  At the
    /// interior knot (`h = sourceDrive`) that gives
    /// `3 / ((2-s)/Δdrive + (1+s)/Δrecovery)`; at the wrap knot the intervals
    /// swap and the weights swap with them, producing the identical value.
    static func sharedTangent(
        sourceDrive s: Double,
        driveSecant: Double,
        recoverySecant: Double
    ) -> Double {
        3 / ((2 - s) / driveSecant + (1 + s) / recoverySecant)
    }

    /// One cubic Hermite segment whose two endpoint tangents are equal.
    ///
    /// `H(u) = startValue + span · (secant · (3u² - 2u³) + tangent · (2u³ - 3u² + u))`
    /// with `u` the normalized position in the segment.  Its derivative is
    /// `tangent + 6u(1-u)(secant - tangent)`, which equals `tangent` at both
    /// ends — that is the C1 property — and stays positive as long as
    /// `tangent < 3 · secant`, which the PCHIP weights guarantee.
    private static func hermite(
        start: Double,
        span: Double,
        startValue: Double,
        secant: Double,
        tangent: Double,
        cycle: Double
    ) -> Double {
        let u = min(1, max(0, (cycle - start) / span))
        let u2 = u * u
        let u3 = u2 * u
        let smooth = 3 * u2 - 2 * u3
        let tangentShape = 2 * u3 - 3 * u2 + u
        return startValue + span * (secant * smooth + tangent * tangentShape)
    }
}
