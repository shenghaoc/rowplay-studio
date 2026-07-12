import Charts
import Foundation
import RowPlayCore
import SwiftUI

struct WorkoutComparisonPanel: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var candidates: [WorkoutDetail]

    @State private var selectedCandidateID: Int?
    @State private var overlayPoints: [CompareOverlayPoint] = []

    var body: some View {
        WorkoutToolSection("Compare") {
            if candidates.isEmpty {
                ContentUnavailableView("No Comparable Workouts", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Compare With", selection: candidateSelection) {
                        ForEach(candidates) { candidate in
                            candidateLabel(candidate)
                                .tag(candidate.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 360, alignment: .leading)

                    if let candidate = selectedCandidate {
                        let verdict = WorkoutComparison.compareVerdict(detail, candidate)
                        Label(verdictText(verdict), systemImage: verdictIcon(verdict))
                            .font(.headline)

                        statsGrid(candidate: candidate)

                        intervalRows(candidate: candidate)

                        overlayChart(points: overlayPoints)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear(perform: alignSelection)
                .onChange(of: candidates.map(\.id)) { _, _ in
                    alignSelection()
                }
                .onChange(of: detail.id) { _, _ in
                    selectedCandidateID = nil
                    alignSelection()
                }
                .task(id: overlayIdentity) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    guard let selectedCandidate else {
                        overlayPoints = []
                        return
                    }
                    let points = makeOverlayPoints(
                        detailStrokes: detail.strokes,
                        candidateStrokes: selectedCandidate.strokes
                    )
                    guard !Task.isCancelled else { return }
                    overlayPoints = points
                }
            }
        }
    }

    private var candidateSelection: Binding<Int> {
        Binding {
            selectedCandidateID ?? candidates.first?.id ?? 0
        } set: { newValue in
            selectedCandidateID = newValue
        }
    }

    private var selectedCandidate: WorkoutDetail? {
        guard let id = selectedCandidateID ?? candidates.first?.id else { return nil }
        return candidates.first { $0.id == id }
    }

    private var overlayIdentity: CompareOverlayIdentity? {
        guard let selectedCandidate else { return nil }
        return CompareOverlayIdentity(
            detailID: detail.id,
            candidateID: selectedCandidate.id,
            detailsRevision: detailsRevision
        )
    }

    private func alignSelection() {
        selectedCandidateID = Self.alignedCandidateID(
            current: selectedCandidateID,
            candidateIDs: candidates.map(\.id)
        )
    }

    static func alignedCandidateID(current: Int?, candidateIDs: [Int]) -> Int? {
        guard let current, candidateIDs.contains(current) else {
            return candidateIDs.first
        }
        return current
    }

    // Keep the original FormatStyle behavior while reusing its value-type configuration.
    // FormatStyle resolves localized component ordering when it formats each date, so a
    // system locale change updates both the names and order of the date components.
    private static let candidateDateFormatStyle = Date.FormatStyle.dateTime
        .year()
        .month(.abbreviated)
        .day()
        .locale(.autoupdatingCurrent)

    private func candidateLabel(_ candidate: WorkoutDetail) -> some View {
        let date = candidate.workout.date.formatted(Self.candidateDateFormatStyle)
        let pace = RowPlayFormatting.pace(candidate.workout.pace)
        return HStack(spacing: 0) {
            Text(date)
            Text(" · ").accessibilityHidden(true)
            Text(candidate.workout.workoutType)
            Text(" · ").accessibilityHidden(true)
            Text(pace)
        }
    }

    private func verdictText(_ verdict: CompareVerdict) -> String {
        switch verdict.winner {
        case .a:
            return "Current workout ahead by \(deltaText(verdict))"
        case .b:
            return "Comparison workout ahead by \(deltaText(verdict))"
        case .tie:
            return "Even result"
        }
    }

    private func verdictIcon(_ verdict: CompareVerdict) -> String {
        switch verdict.winner {
        case .a: return "checkmark.seal"
        case .b: return "arrow.left.arrow.right"
        case .tie: return "equal"
        }
    }

    private func deltaText(_ verdict: CompareVerdict) -> String {
        if let timeDeltaSec = verdict.timeDeltaSec {
            return RowPlayFormatting.time(abs(timeDeltaSec), tenths: true)
        }
        if let paceDelta = verdict.paceDelta {
            return "\(formatDouble(abs(paceDelta))) sec/500m"
        }
        return "0.0 sec"
    }

    private func statsGrid(candidate: WorkoutDetail) -> some View {
        let current = WorkoutComparison.sideStats(detail)
        let comparison = WorkoutComparison.sideStats(candidate)

        return Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
            GridRow {
                Text("Metric")
                Text("Current")
                Text("Comparison")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            metricRow("Time", RowPlayFormatting.time(current.time, tenths: true), RowPlayFormatting.time(comparison.time, tenths: true))
            metricRow("Pace", RowPlayFormatting.pace(current.pace), RowPlayFormatting.pace(comparison.pace))
            metricRow("Avg Watts", "\(current.avgWatts)", "\(comparison.avgWatts)")
            metricRow("Best 5s", "\(current.best5sPower)", "\(comparison.best5sPower)")
            metricRow("Avg HR", current.avgHr.map(String.init) ?? "-", comparison.avgHr.map(String.init) ?? "-")
            metricRow("Peak HR", current.peakHr.map(String.init) ?? "-", comparison.peakHr.map(String.init) ?? "-")
            metricRow("DPS", formatDouble(current.avgDps), formatDouble(comparison.avgDps))
            metricRow("Consistency", "\(formatDouble(current.paceConsistency))%", "\(formatDouble(comparison.paceConsistency))%")
        }
        .font(.callout)
    }

    private func metricRow(_ label: String, _ current: String, _ comparison: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(current)
                .monospacedDigit()
            Text(comparison)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func intervalRows(candidate: WorkoutDetail) -> some View {
        if let rows = WorkoutComparison.compareIntervalReps(detail, candidate), !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Intervals")
                    .font(.subheadline.weight(.semibold))

                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                    GridRow {
                        Text("#")
                        Text("Current")
                        Text("Comparison")
                        Text("Delta")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(rows.prefix(8), id: \.index) { row in
                        GridRow {
                            Text("\(row.index)")
                            Text(RowPlayFormatting.pace(row.paceA))
                            Text(RowPlayFormatting.pace(row.paceB))
                            Text("\(formatSigned(row.paceDelta)) sec/500m")
                        }
                        .monospacedDigit()
                    }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func overlayChart(points: [CompareOverlayPoint]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pace Overlay")
                    .font(.subheadline.weight(.semibold))

                Chart(points) { point in
                    LineMark(
                        x: .value("Distance", point.distance),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(by: .value("Workout", point.series))
                }
                .chartXAxisLabel("metres")
                .chartYAxisLabel("sec/500m")
                .frame(height: 220)
            }
        }
    }

    private func makeOverlayPoints(
        detailStrokes: [Stroke],
        candidateStrokes: [Stroke]
    ) -> [CompareOverlayPoint] {
        guard let overlay = WorkoutComparison.buildDistanceOverlay(
            detailStrokes,
            candidateStrokes
        ) else {
            return []
        }

        var points: [CompareOverlayPoint] = []
        for index in overlay.xs.indices {
            let distance = overlay.xs[index]
            if let pace = overlay.paceA[index] {
                points.append(CompareOverlayPoint(
                    id: "current-\(index)",
                    distance: distance,
                    pace: pace,
                    series: "Current"
                ))
            }
            if let pace = overlay.paceB[index] {
                points.append(CompareOverlayPoint(
                    id: "comparison-\(index)",
                    distance: distance,
                    pace: pace,
                    series: "Comparison"
                ))
            }
        }
        return points
    }

    private func formatDouble(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formatSigned(_ value: Double) -> String {
        let formatted = formatDouble(abs(value))
        if value > 0 {
            return "+\(formatted)"
        }
        if value < 0 {
            return "-\(formatted)"
        }
        return formatted
    }
}

private struct CompareOverlayIdentity: Equatable, Sendable {
    let detailID: Int
    let candidateID: Int
    let detailsRevision: UInt64
}

private struct CompareOverlayPoint: Identifiable {
    let id: String
    let distance: Double
    let pace: Double
    let series: String
}
