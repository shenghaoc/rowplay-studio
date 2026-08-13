import XCTest
@testable import RowPlayCore

final class ReplayAthletePhaseMapTests: XCTestCase {
    // MARK: - Helpers

    private func clipFraction(
        cycle: Double,
        driveFrac: Double,
        driveEnd: Double
    ) -> Double {
        ReplayAthletePhaseMap.clipFraction(
            sample: ReplayAthleteMotionSample(phase: 0, cycleFrac: cycle, driveFrac: driveFrac),
            authoredDriveEnd: driveEnd
        )
    }

    /// One-sided secant slopes taken the same distance either side of the
    /// drive/recovery seam. For a C1 map the two agree up to the O(h)
    /// truncation term; for the two-segment linear map they differ by a
    /// constant that does not shrink with `h`.
    private func seamSlopeGap(driveFrac: Double, driveEnd: Double, h: Double) -> Double {
        let seam = driveFrac
        let atSeam = clipFraction(cycle: seam, driveFrac: driveFrac, driveEnd: driveEnd)
        let before = clipFraction(cycle: seam - h, driveFrac: driveFrac, driveEnd: driveEnd)
        let after = clipFraction(cycle: seam + h, driveFrac: driveFrac, driveEnd: driveEnd)
        return abs((after - atSeam) / h - (atSeam - before) / h)
    }

    /// Same measurement across the cycle wrap, where `f(1⁻)` meets `f(0⁺)`.
    private func wrapSlopeGap(driveFrac: Double, driveEnd: Double, h: Double) -> Double {
        let incoming = (1 - clipFraction(cycle: 1 - h, driveFrac: driveFrac, driveEnd: driveEnd)) / h
        let outgoing = clipFraction(cycle: h, driveFrac: driveFrac, driveEnd: driveEnd) / h
        return abs(outgoing - incoming)
    }

    /// Authored `driveEnd` values in the bundled motion manifest.
    private static let authoredDriveEnds: [Double] = [0.38, 0.34, 0.5]
    /// Range `ReplayStrokePose.driveFraction` clamps RowErg/SkiErg onto.
    private static let measuredDriveFractions: [Double] = stride(from: 0.28, through: 0.46, by: 0.01).map { $0 }

    // MARK: - Landmarks and monotonicity

    func testClipFractionMapsDriveAndRecoveryMonotonically() {
        let driveEnd = 0.38
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(phase: 0, cycleFrac: 0, driveFrac: 0.4),
                authoredDriveEnd: driveEnd
            ),
            0,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(phase: 0, cycleFrac: 0.4, driveFrac: 0.4),
                authoredDriveEnd: driveEnd
            ),
            driveEnd,
            accuracy: 1e-12
        )
        var previous = -1.0
        for step in 0..<100 {
            let fraction = ReplayAthletePhaseMap.clipFraction(
                sample: ReplayAthleteMotionSample(
                    phase: 0,
                    cycleFrac: Double(step) / 100,
                    driveFrac: 0.4
                ),
                authoredDriveEnd: driveEnd
            )
            XCTAssertGreaterThanOrEqual(fraction, previous)
            previous = fraction
        }
    }

    /// Dense grid across the full clamped drive-share square: strictly
    /// increasing, never leaving [0, 1], and hitting every landmark exactly.
    func testClipFractionIsMonotoneAndBoundedAcrossDriveShareGrid() {
        let samplesPerCycle = 400
        for sourceStep in 0...90 {
            let sourceDrive = 0.05 + Double(sourceStep) * 0.01
            for clipStep in 0...90 {
                let clipDrive = 0.05 + Double(clipStep) * 0.01
                var previous = -Double.infinity
                for step in 0..<samplesPerCycle {
                    let cycle = Double(step) / Double(samplesPerCycle)
                    let value = clipFraction(
                        cycle: cycle,
                        driveFrac: sourceDrive,
                        driveEnd: clipDrive
                    )
                    XCTAssertTrue(
                        value.isFinite,
                        "non-finite at cycle \(cycle) source \(sourceDrive) clip \(clipDrive)"
                    )
                    // No overshoot below 0 or above 1 anywhere in the cycle.
                    XCTAssertGreaterThanOrEqual(value, 0)
                    XCTAssertLessThanOrEqual(value, 1)
                    // No reversal: strictly increasing at this sampling rate.
                    XCTAssertGreaterThan(
                        value,
                        previous,
                        "reversal at cycle \(cycle) source \(sourceDrive) clip \(clipDrive)"
                    )
                    previous = value
                }
                // f(0) = 0 and f(sourceDrive) = clipDrive to 1e-12.
                XCTAssertEqual(
                    clipFraction(cycle: 0, driveFrac: sourceDrive, driveEnd: clipDrive),
                    0,
                    accuracy: 1e-12
                )
                XCTAssertEqual(
                    clipFraction(cycle: sourceDrive, driveFrac: sourceDrive, driveEnd: clipDrive),
                    clipDrive,
                    accuracy: 1e-12,
                    "landmark missed for source \(sourceDrive) clip \(clipDrive)"
                )
            }
        }
    }

    /// `f(1) = 1` is the wrap landmark; `wrapUnit` never feeds exactly 1 to the
    /// map, so it is checked as a one-sided limit.
    func testClipFractionApproachesOneAtCycleEnd() {
        for clipDrive in Self.authoredDriveEnds {
            for sourceDrive in Self.measuredDriveFractions {
                let value = clipFraction(
                    cycle: 1 - 1e-9,
                    driveFrac: sourceDrive,
                    driveEnd: clipDrive
                )
                XCTAssertEqual(value, 1, accuracy: 1e-8)
            }
        }
    }

    /// When the native drive share already equals the authored one the map has
    /// nothing to re-time and collapses to the identity.
    func testClipFractionIsIdentityWhenDriveSharesMatch() {
        for share in [0.28, 0.34, 0.38, 0.46, 0.5] {
            for step in 0..<200 {
                let cycle = Double(step) / 200
                XCTAssertEqual(
                    clipFraction(cycle: cycle, driveFrac: share, driveEnd: share),
                    cycle,
                    accuracy: 1e-12
                )
            }
        }
    }

    // MARK: - C1 continuity

    /// Across the production drive-share range the one-sided slopes at the
    /// drive/recovery seam agree to 1e-5 at h = 1e-6 (worst measured 9.3e-6).
    /// The two-segment linear map differed by 24.5%–65.4% of the incoming
    /// slope over the same range.
    func testSeamSlopeIsContinuousAcrossProductionDriveShares() {
        for driveEnd in Self.authoredDriveEnds {
            for driveFrac in Self.measuredDriveFractions {
                let gap = seamSlopeGap(driveFrac: driveFrac, driveEnd: driveEnd, h: 1e-6)
                XCTAssertLessThan(
                    gap,
                    1e-5,
                    "seam slope gap \(gap) for driveFrac \(driveFrac) driveEnd \(driveEnd)"
                )
            }
        }
    }

    /// The same continuity holds across the cycle wrap, which the two-segment
    /// linear map also broke — the catch carried a step of the same size in
    /// the opposite direction.
    func testWrapSlopeIsContinuousAcrossProductionDriveShares() {
        for driveEnd in Self.authoredDriveEnds {
            for driveFrac in Self.measuredDriveFractions {
                let gap = wrapSlopeGap(driveFrac: driveFrac, driveEnd: driveEnd, h: 1e-6)
                XCTAssertLessThan(
                    gap,
                    1e-5,
                    "wrap slope gap \(gap) for driveFrac \(driveFrac) driveEnd \(driveEnd)"
                )
            }
        }
    }

    /// Extremes of the clamped square: 2e-3 at h = 1e-6 (worst measured
    /// 1.14e-3, at the degenerate 0.95/0.05 corner where the two secants
    /// differ by a factor of 361).
    func testSeamSlopeIsContinuousAcrossFullDriveShareGrid() {
        for sourceStep in 0...90 {
            let sourceDrive = 0.05 + Double(sourceStep) * 0.01
            for clipStep in 0...90 {
                let clipDrive = 0.05 + Double(clipStep) * 0.01
                XCTAssertLessThan(
                    seamSlopeGap(driveFrac: sourceDrive, driveEnd: clipDrive, h: 1e-6),
                    2e-3
                )
                XCTAssertLessThan(
                    wrapSlopeGap(driveFrac: sourceDrive, driveEnd: clipDrive, h: 1e-6),
                    2e-3
                )
            }
        }
    }

    /// The decisive C1 signature: the residual gap is the O(h) truncation term
    /// of the one-sided secants, so halving h halves it. A C0-only map would
    /// hold its gap constant.
    func testSeamSlopeGapShrinksLinearlyWithStep() {
        for driveEnd in Self.authoredDriveEnds {
            for driveFrac in [0.28, 0.34, 0.42, 0.46] {
                let coarse = seamSlopeGap(driveFrac: driveFrac, driveEnd: driveEnd, h: 1e-5)
                let fine = seamSlopeGap(driveFrac: driveFrac, driveEnd: driveEnd, h: 5e-6)
                guard coarse > 1e-12 else { continue }
                let ratio = fine / coarse
                XCTAssertEqual(
                    ratio,
                    0.5,
                    accuracy: 0.05,
                    "ratio \(ratio) for driveFrac \(driveFrac) driveEnd \(driveEnd)"
                )
            }
        }
    }

    // MARK: - Fallbacks and drive predicate

    func testClipFractionUsesPhaseAndFiniteFallbacks() {
        let sample = ReplayAthleteMotionSample(
            phase: .pi,
            cycleFrac: .nan,
            driveFrac: .infinity
        )
        // Non-finite cycleFrac falls back to phase/2pi = 0.5, non-finite
        // driveFrac to 0.4, and non-finite authoredDriveEnd to 0.5 — the same
        // clamped fallbacks as before. Only the interpolation between those
        // landmarks changed, so the value is the Hermite one (0.59334...)
        // rather than the two-segment linear 7/12.
        let mapped = ReplayAthletePhaseMap.clipFraction(sample: sample, authoredDriveEnd: .nan)
        XCTAssertEqual(mapped, 0.593_343_343_343_343_4, accuracy: 1e-12)
        // Proves the fallbacks — not a coincidence of this literal — by
        // feeding the resolved values explicitly and getting the same result.
        XCTAssertEqual(
            mapped,
            clipFraction(cycle: 0.5, driveFrac: 0.4, driveEnd: 0.5),
            accuracy: 1e-15
        )
        XCTAssertTrue(ReplayAthletePhaseMap.isDrive(clipFraction: -0.9, authoredDriveEnd: 0.4))
        XCTAssertFalse(ReplayAthletePhaseMap.isDrive(clipFraction: 0.8, authoredDriveEnd: 0.4))
    }

    func testClipFractionClampsDegenerateDriveShares() {
        // Out-of-range drive shares clamp to [0.05, 0.95] rather than dividing
        // by zero, and still land the landmark on the clamped values.
        for (driveFrac, clampedSource) in [(-3.0, 0.05), (0.0, 0.05), (1.0, 0.95), (17.0, 0.95)] {
            for (driveEnd, clampedClip) in [(-1.0, 0.05), (2.0, 0.95)] {
                let value = clipFraction(
                    cycle: clampedSource,
                    driveFrac: driveFrac,
                    driveEnd: driveEnd
                )
                XCTAssertEqual(value, clampedClip, accuracy: 1e-12)
            }
        }
    }

    /// `isDrive` must classify a mapped fraction exactly as the source cycle
    /// was classified, for every drive share pair — including the non-finite
    /// authored value, where the predicate now clamps like the map does.
    func testIsDriveAgreesWithSourceCycleClassification() {
        for sourceStep in 0...90 {
            let sourceDrive = 0.05 + Double(sourceStep) * 0.01
            for clipDrive in Self.authoredDriveEnds + [0.05, 0.95] {
                for step in 0..<200 {
                    let cycle = Double(step) / 200
                    // Skip the knife-edge where the two grids coincide to
                    // within a rounding step: there `f(cycle)` and `clipDrive`
                    // are the same double, so the strict `<` in either
                    // predicate is decided by representation, not by the map.
                    guard abs(cycle - sourceDrive) > 1e-9 else { continue }
                    let mapped = clipFraction(
                        cycle: cycle,
                        driveFrac: sourceDrive,
                        driveEnd: clipDrive
                    )
                    XCTAssertEqual(
                        ReplayAthletePhaseMap.isDrive(
                            clipFraction: mapped,
                            authoredDriveEnd: clipDrive
                        ),
                        cycle < sourceDrive,
                        "isDrive disagreed at cycle \(cycle) source \(sourceDrive) clip \(clipDrive)"
                    )
                }
            }
        }
    }

    func testIsDriveClampsNonFiniteAuthoredDriveEnd() {
        // A non-finite authored drive end resolves to the same 0.5 the map
        // uses, so the predicate stays usable instead of always returning
        // false through a NaN comparison.
        XCTAssertTrue(ReplayAthletePhaseMap.isDrive(clipFraction: 0.25, authoredDriveEnd: .nan))
        XCTAssertFalse(ReplayAthletePhaseMap.isDrive(clipFraction: 0.75, authoredDriveEnd: .nan))
    }
}
