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
public enum ReplayAthletePhaseMap {
    /// Map one native stroke cycle onto the authored clip's drive/recovery
    /// split without introducing an independent animation clock.
    public static func clipFraction(
        sample: ReplayAthleteMotionSample,
        authoredDriveEnd: Double
    ) -> Double {
        let phaseCycle = ReplayAthleteMotionTable.wrapUnit(sample.phase / (2 * Double.pi))
        let cycle = sample.cycleFrac.isFinite
            ? ReplayAthleteMotionTable.wrapUnit(sample.cycleFrac)
            : phaseCycle
        let sourceDrive = min(
            0.95,
            max(0.05, sample.driveFrac.isFinite ? sample.driveFrac : 0.4)
        )
        let clipDrive = min(
            0.95,
            max(0.05, authoredDriveEnd.isFinite ? authoredDriveEnd : 0.5)
        )
        if cycle < sourceDrive {
            return (cycle / sourceDrive) * clipDrive
        }
        return clipDrive + ((cycle - sourceDrive) / (1 - sourceDrive)) * (1 - clipDrive)
    }

    public static func isDrive(clipFraction: Double, authoredDriveEnd: Double) -> Bool {
        ReplayAthleteMotionTable.wrapUnit(clipFraction) < authoredDriveEnd
    }
}
