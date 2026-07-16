import Foundation
import RowPlayCore
import SwiftUI

/// Rival selection and at-a-glance race-gap controls for replay.
///
/// Import execution and rival lifecycle state remain owned by ``ReplayView``;
/// this view only presents that state and routes user intent through bindings
/// and actions.
struct ReplayRivalControlView: View {
    private static let candidateDateStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .omitted
    ).locale(.autoupdatingCurrent)

    let detail: WorkoutDetail
    let ghostCandidates: [WorkoutDetail]
    let ghostCandidateByID: [Int: WorkoutDetail]
    let activeRival: ReplayRival?
    let currentFrame: ReplayFrame
    let replayTime: TimeInterval
    let distanceUnit: DistanceUnit
    let locale: Locale
    let isImportingRival: Bool
    @Binding var showPaceEditor: Bool
    @Binding var paceInputText: String
    @Binding var paceValidationError: String?
    @Binding var showFileImporter: Bool
    @Binding var rivalErrorMessage: String?
    let selectRival: (ReplayRival?) -> Void
    let applyConstantPace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controlBand

            if let rivalErrorMessage {
                Text(rivalErrorMessage)
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(AppDesign.alertRed)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Rival error")
                    .accessibilityValue(rivalErrorMessage)
            }

            if isImportingRival {
                ProgressView("Importing rival…")
                    .controlSize(.small)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Importing rival")
            }
        }
        .popover(isPresented: $showPaceEditor, arrowEdge: .bottom) {
            paceEditorPopover
        }
    }

    private var controlBand: some View {
        HStack(spacing: AppDesign.Spacing.medium) {
            Menu {
                Button {
                    selectRival(nil)
                } label: {
                    HStack {
                        Text("No Rival")
                        if activeRival == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !ghostCandidates.isEmpty {
                    Button {
                        if let best = ghostCandidates.first,
                           let rival = ReplayRivalFactory.makeSessionRival(from: best) {
                            selectRival(rival)
                        }
                    } label: {
                        HStack {
                            Text("Best Match")
                            if isBestMatchSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()
                    ForEach(ghostCandidates) { candidate in
                        Button {
                            if let rival = ReplayRivalFactory.makeSessionRival(from: candidate) {
                                selectRival(rival)
                            }
                        } label: {
                            HStack {
                                candidateLabel(for: candidate)
                                if activeRival?.sessionWorkoutID == candidate.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Set Constant Pace…") {
                    paceInputText = PaceInput.formatPaceInput(detail.workout.pace)
                    paceValidationError = nil
                    showPaceEditor = true
                }

                Button("Import Rival File…") {
                    showFileImporter = true
                }
                .disabled(isImportingRival)
                #if os(macOS)
                .help(isImportingRival
                    ? "A rival file is already being imported"
                    : "Choose a CSV, TCX, or FIT rival file")
                #endif
            } label: {
                Label("Replay rival", systemImage: "person.2.fill")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Replay rival")
            .accessibilityValue(rivalAccessibilityValue)
            #if os(macOS)
            .help("Choose a past session, constant pace, or imported file rival")
            #endif

            if let activeRival {
                rivalGapDisplay(for: activeRival)
            }

            Spacer()

            if activeRival != nil {
                Button {
                    selectRival(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove replay rival")
                #if os(macOS)
                .help("Remove replay rival")
                #endif
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private var isBestMatchSelected: Bool {
        guard let bestID = ghostCandidates.first?.id else { return false }
        return activeRival?.sessionWorkoutID == bestID
    }

    private var paceEditorPopover: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
            Text("Constant pace")
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)
            TextField("M:SS", text: $paceInputText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .accessibilityLabel("Constant pace input")
                .onSubmit(applyConstantPace)
            if let paceValidationError {
                Text(paceValidationError)
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(AppDesign.alertRed)
                    .accessibilityLabel("Pace validation error")
                    .accessibilityValue(paceValidationError)
            }
            HStack {
                Button("Cancel") {
                    showPaceEditor = false
                    paceValidationError = nil
                }
                Button("Set Pace", action: applyConstantPace)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func candidateLabel(for candidate: WorkoutDetail) -> some View {
        let workout = candidate.workout
        let date = workout.date.formatted(Self.candidateDateStyle.locale(locale))
        let distance = RowPlayFormatting.distance(workout.distance, unit: distanceUnit)
        let pace = RowPlayFormatting.pace(workout.pace)
        return Text("\(date) · \(distance) · \(pace)")
            .accessibilityLabel("\(date), \(distance), \(pace)")
    }

    private var rivalAccessibilityValue: String {
        guard let activeRival else {
            return "No rival selected"
        }
        switch activeRival.kind {
        case .session:
            if let id = activeRival.sessionWorkoutID,
               let candidate = ghostCandidateByID[id] {
                let workout = candidate.workout
                let distance = RowPlayFormatting.distance(workout.distance, unit: distanceUnit)
                let pace = RowPlayFormatting.pace(workout.pace)
                let date = workout.date.formatted(Self.candidateDateStyle.locale(locale))
                return "Rival: \(distance) at \(pace) from \(date)"
            }
            return "Past session rival"
        case .constantPace:
            if let pace = activeRival.targetPace {
                return "Pace boat \(RowPlayFormatting.pace(pace))"
            }
            return "Pace boat"
        case .importedFile:
            if let name = activeRival.localFileName {
                return "Imported rival \(name)"
            }
            return "Imported rival"
        }
    }

    private func rivalGapDisplay(for rival: ReplayRival) -> some View {
        let ghostDistance = ReplayRaceGap.ghostDistance(elapsed: replayTime, strokes: rival.strokes)
        let gapMeters = ReplayRaceGap.raceGapMeters(
            playerDistance: currentFrame.d,
            ghostDistance: ghostDistance
        )
        let gapSeconds = ReplayRaceGap.raceGapSeconds(
            gapMeters: gapMeters,
            playerPacePer500m: currentFrame.pace
        )
        let gapColor = AppDesign.deltaColor(gapMeters, higherIsBetter: true)
        let shortLabel = rivalShortLabel(rival)
        let distanceLabel = ReplayRivalGapFormatting.metersLabel(
            gapMeters,
            unit: distanceUnit
        )
        let secondsLabel = ReplayRivalGapFormatting.secondsLabel(gapSeconds)

        return HStack(spacing: AppDesign.Spacing.small) {
            Text(shortLabel)
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)

            Text(distanceLabel)
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)

            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(secondsLabel)
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Race gap against \(shortLabel)")
        .accessibilityValue("\(distanceLabel), \(secondsLabel)")
    }

    private func rivalShortLabel(_ rival: ReplayRival) -> String {
        switch rival.kind {
        case .session:
            if let id = rival.sessionWorkoutID,
               let candidate = ghostCandidateByID[id] {
                return candidate.workout.date.formatted(Self.candidateDateStyle.locale(locale))
            }
            return "Session"
        case .constantPace:
            return rival.displayLabel
        case .importedFile:
            return rival.localFileName ?? "Imported"
        }
    }
}

enum ReplayRivalGapFormatting {
    static func metersLabel(_ meters: Double, unit: DistanceUnit) -> String {
        let safeMeters = meters.isFinite ? meters : 0
        if abs(safeMeters) < 0.5 { return "Level" }
        let prefix = safeMeters > 0 ? "Ahead" : "Behind"
        let distance = RowPlayFormatting.distance(abs(safeMeters), unit: unit)
        return "\(prefix) \(distance)"
    }

    static func secondsLabel(_ seconds: Double) -> String {
        let safeSeconds = seconds.isFinite ? seconds : 0
        let absoluteSeconds = abs(safeSeconds)
        if absoluteSeconds < 0.05 { return "0.0 s" }
        let sign = safeSeconds > 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", absoluteSeconds)) s"
    }
}

/// Refreshes only past-session rivals when the underlying workout library
/// changes. Constant-pace and imported rivals are user-owned selections and
/// therefore survive unrelated library refreshes.
enum ReplaySessionRivalReconciler {
    static func reconcile(
        activeRival: ReplayRival?,
        candidates: [WorkoutDetail]
    ) -> ReplayRival? {
        guard let activeRival, activeRival.kind == .session else {
            return activeRival
        }
        guard let workoutID = activeRival.sessionWorkoutID,
              let refreshedDetail = candidates.first(where: { $0.id == workoutID }) else {
            return nil
        }
        return ReplayRivalFactory.makeSessionRival(from: refreshedDetail)
    }
}
