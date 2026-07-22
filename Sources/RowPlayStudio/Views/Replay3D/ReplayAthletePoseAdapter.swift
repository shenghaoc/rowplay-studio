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
        let driveEnd = contract.clip(for: sport)?.driveEnd ?? defaultDriveEnd(for: sport)
        return ReplayAthleteCatalog.clipFraction(
            sample: sample,
            authoredDriveEnd: driveEnd
        )
    }

    /// Apply deterministic phase sampling to an independent athlete instance.
    @MainActor
    func apply(
        sample: ReplayAthleteMotionSample,
        sport: Sport,
        to instance: ReplayAthleteInstance
    ) {
        let fraction = clipFraction(sport: sport, sample: sample)
        instance.seek(toClipFraction: fraction)
    }

    /// Landmark progress checks used by dense-cycle movement tests.
    func landmarkFraction(sport: Sport, name: String) -> Double? {
        contract.clip(for: sport)?.phaseLandmarks[name]
    }

    /// True when `fraction` is within the drive half of the authored clip.
    func isDrive(sport: Sport, clipFraction: Double) -> Bool {
        let driveEnd = contract.clip(for: sport)?.driveEnd ?? defaultDriveEnd(for: sport)
        return ReplayAthleteCatalog.wrapUnit(clipFraction) < driveEnd
    }

    private func defaultDriveEnd(for sport: Sport) -> Double {
        switch sport {
        case .rower: 0.38
        case .skierg: 0.34
        case .bike: 0.5
        }
    }
}
