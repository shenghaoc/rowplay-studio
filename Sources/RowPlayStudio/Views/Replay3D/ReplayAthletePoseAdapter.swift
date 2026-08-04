import Foundation
import RealityKit
import RowPlayCore

/// Maps native replay phase onto the versioned V4 sport animation.
///
/// Movement physics remain owned by upstream PR #171. When landmarks or drive
/// ends change, update the bundled contract and focused adapter tests — not the
/// asset loading pipeline. Pure fraction math is nonisolated; only instance
/// seeking touches RealityKit on the main actor.
struct ReplayAthletePoseAdapter: Sendable {
    let contract: ReplayAthleteContract

    init(contract: ReplayAthleteContract) {
        self.contract = contract
    }

    /// Clip fraction for a sport at the given motion sample.
    func clipFraction(sport: Sport, sample: ReplayAthleteMotionSample) -> Double {
        let driveEnd = requiredClip(for: sport).driveEnd
        return ReplayAthletePhaseMap.clipFraction(
            sample: sample,
            authoredDriveEnd: driveEnd
        )
    }

    /// Apply deterministic phase sampling to an independent athlete instance.
    @MainActor
    @discardableResult
    func apply(
        sample: ReplayAthleteMotionSample,
        sport: Sport,
        to instance: ReplayAthleteInstance
    ) -> Bool {
        let fraction = clipFraction(sport: sport, sample: sample)
        return instance.seek(toClipFraction: fraction)
    }

    /// Landmark progress checks used by dense-cycle movement tests.
    func landmarkFraction(sport: Sport, name: String) -> Double? {
        contract.clip(for: sport)?.phaseLandmarks[name]
    }

    /// True when `fraction` is within the drive half of the authored clip.
    func isDrive(sport: Sport, clipFraction: Double) -> Bool {
        ReplayAthletePhaseMap.isDrive(
            clipFraction: clipFraction,
            authoredDriveEnd: requiredClip(for: sport).driveEnd
        )
    }

    private func requiredClip(for sport: Sport) -> ReplayAthleteClipSpec {
        guard let clip = contract.clip(for: sport) else {
            preconditionFailure("Validated athlete contract missing \(sport.rawValue) clip")
        }
        return clip
    }
}
