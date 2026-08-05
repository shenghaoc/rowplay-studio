import RowPlayCore
import RowPlayPlatform
import SwiftUI

/// Staged-app host that constructs the production `ReplayView` from
/// deterministic demo workouts. It never builds a parallel renderer.
struct ReplayAcceptanceHarnessView: View {
    let configuration: ReplayAcceptanceConfiguration
    @EnvironmentObject private var preferences: AppPreferences

    private var detail: WorkoutDetail {
        Self.detail(for: configuration.sport)
    }

    private var ghostCandidates: [WorkoutDetail] {
        Self.ghostCandidates(for: configuration.sport, excluding: detail.id)
    }

    private var initialGhostID: Int? {
        guard configuration.rival == .session else { return nil }
        return ghostCandidates.first?.id
    }

    var body: some View {
        ReplayView(
            detail: detail,
            ghostCandidates: ghostCandidates,
            ghostCandidatesRevision: 1,
            initialGhostID: initialGhostID,
            initialConfiguration: configuration.makeViewConfiguration()
        )
        .preferredColorScheme(configuration.theme == .dark ? .dark : .light)
        .frame(
            minWidth: configuration.windowWidth,
            idealWidth: configuration.windowWidth,
            minHeight: configuration.windowHeight,
            idealHeight: configuration.windowHeight
        )
        .onAppear {
            ReplayAcceptanceMetricsStore.beginScenario(
                scenarioID: nil,
                selectedQuality: configuration.quality,
                effectiveQuality: configuration.quality,
                livePresent: true,
                rivalPresent: configuration.rival != .none
            )
            // Periodic flush so SIGTERM/kill still leave metrics on disk.
            if let outputDirectory = configuration.outputDirectory {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(20))
                    ReplayAcceptanceMetricsStore.endAndEmit(
                        outputDirectory: outputDirectory
                    )
                }
            }
        }
        .onDisappear {
            ReplayAcceptanceMetricsStore.endAndEmit(
                outputDirectory: configuration.outputDirectory
            )
        }
        // Acceptance never writes QA state into user preferences.
        .onAppear {
            _ = preferences
        }
    }

    static func detail(for sport: Sport) -> WorkoutDetail {
        let id = ReplayAcceptanceConfiguration.demoWorkoutID(for: sport)
        if let match = DemoWorkoutLibrary.details.first(where: { $0.id == id }) {
            return match
        }
        // Deterministic fallback keeps harness construction total.
        return DemoWorkoutLibrary.details.first { $0.workout.sport == sport }
            ?? DemoWorkoutLibrary.details[0]
    }

    static func ghostCandidates(for sport: Sport, excluding id: Int) -> [WorkoutDetail] {
        DemoWorkoutLibrary.details.filter {
            $0.workout.sport == sport && $0.id != id && $0.workout.hasStrokeData
        }
    }

    static func resolvedRival(
        mode: ReplayAcceptanceConfiguration.RivalMode,
        detail: WorkoutDetail,
        candidates: [WorkoutDetail]
    ) -> ReplayRival? {
        switch mode {
        case .none:
            return nil
        case .session:
            guard let candidate = candidates.first else { return nil }
            return ReplayRivalFactory.makeSessionRival(from: candidate)
        case .pace:
            let pace = detail.workout.pace
            return ReplayRivalFactory.makeConstantPaceRival(
                pacePer500m: pace,
                player: detail.workout
            )
        }
    }
}
