import Charts
import Foundation
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct WorkoutComparisonPanel: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var candidates: [WorkoutDetail]

    @EnvironmentObject private var preferences: AppPreferences
    @State private var selectedCandidateID: Int?
    @State private var overlayPoints: [CompareOverlayPoint] = []
    @State private var overlayPaceDomain: ClosedRange<Double> = -180 ... -60

    var body: some View {
        let candidateIDs = candidates.map(\.id)

        return WorkoutToolSection("Compare") {
            if candidates.isEmpty {
                ContentUnavailableView("No Comparable Workouts", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xLarge) {
                    Picker("Compare With", selection: candidateSelection) {
                        ForEach(candidates) { candidate in
                            candidateLabel(candidate)
                                .tag(candidate.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 420, maxWidth: 480, alignment: .leading)

                    if let candidate = selectedCandidate {
                        let verdict = WorkoutComparison.compareVerdict(detail, candidate)
                        Label(verdictText(verdict), systemImage: verdictIcon(verdict))
                            .font(AppDesign.Typography.sectionHeadline)
                            .foregroundStyle(verdictColor(verdict))

                        statsGrid(candidate: candidate)

                        intervalRows(candidate: candidate)

                        overlayChart(points: overlayPoints)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear(perform: alignSelection)
                .onChange(of: candidateIDs) { _, _ in
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
                        overlayPaceDomain = -180 ... -60
                        return
                    }
                    let points = makeOverlayPoints(
                        detailStrokes: detail.strokes,
                        candidateStrokes: selectedCandidate.strokes
                    )
                    guard !Task.isCancelled else { return }
                    overlayPoints = points
                    overlayPaceDomain = Self.paceChartDomain(for: points.map(\.pace))
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

    static func paceChartDomain(for paces: [Double]) -> ClosedRange<Double> {
        let validPaces = paces.filter { $0.isFinite && $0 > 0 }
        guard let fastest = validPaces.min(), let slowest = validPaces.max() else {
            return -180 ... -60
        }
        let padding = max((slowest - fastest) * 0.12, 3)
        return -(slowest + padding) ... -(fastest - padding)
    }

    private func candidateLabel(_ candidate: WorkoutDetail) -> some View {
        let date = candidate.workout.date.formatted(.dateTime.year().month(.abbreviated).day())
        let pace = RowPlayFormatting.pace(candidate.workout.pace)
        let type = candidate.workout.workoutType
        return Text("\(date) · \(type) · \(pace)")
            .accessibilityLabel("\(date), \(type), \(pace)")
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

        return Grid(alignment: .leading, horizontalSpacing: AppDesign.Spacing.xxxLarge, verticalSpacing: AppDesign.Spacing.medium) {
            GridRow {
                Text("Metric")
                Text("Current")
                Text("Comparison")
            }
            .font(AppDesign.Typography.compactLabel)
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
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                Text("Intervals")
                    .font(AppDesign.Typography.sectionHeadline)

                Grid(alignment: .leading, horizontalSpacing: AppDesign.Spacing.xxxLarge, verticalSpacing: AppDesign.Spacing.small) {
                    GridRow {
                        Text("#")
                        Text("Current")
                        Text("Comparison")
                        Text("Delta")
                    }
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(.secondary)

                    ForEach(rows.prefix(8), id: \.index) { row in
                        GridRow {
                            Text("\(row.index)")
                            Text(RowPlayFormatting.pace(row.paceA))
                            Text(RowPlayFormatting.pace(row.paceB))
                            Text("\(formatSigned(row.paceDelta)) sec/500m")
                                .foregroundStyle(AppDesign.deltaColor(row.paceDelta, threshold: 0.1))
                        }
                        .monospacedDigit()
                    }
                }
                .font(AppDesign.Typography.compactLabel)
            }
        }
    }

    @ViewBuilder
    private func overlayChart(points: [CompareOverlayPoint]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                Text("Pace Overlay")
                    .font(AppDesign.Typography.sectionHeadline)

                Chart(points) { point in
                    LineMark(
                        x: .value("Distance", chartDistance(point.distance)),
                        y: .value("Pace", -point.pace)
                    )
                    .foregroundStyle(by: .value("Workout", point.series))
                }
                .chartForegroundStyleScale([
                    "Current": AppDesign.primaryBlue,
                    "Comparison": AppDesign.comparisonOrange
                ])
                .chartXAxisLabel(distanceAxisLabel)
                .chartYAxisLabel("Pace (/500m)")
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        if let seconds = value.as(Double.self) {
                            AxisValueLabel(RowPlayFormatting.pace(abs(seconds)))
                        }
                    }
                }
                .chartYScale(domain: overlayPaceDomain)
                .frame(height: AppDesign.Chart.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pace comparison chart")
                .accessibilityValue(overlayAccessibilityValue)
            }
        }
    }

    private func chartDistance(_ metres: Double) -> Double {
        preferences.distanceUnit == .imperial ? metres / 1_609.344 : metres / 1_000
    }

    private var distanceAxisLabel: String {
        preferences.distanceUnit == .imperial ? "Distance (mi)" : "Distance (km)"
    }

    private var overlayAccessibilityValue: String {
        guard let selectedCandidate else { return "No comparison selected" }
        return "Current average \(RowPlayFormatting.pace(detail.workout.pace)); comparison average \(RowPlayFormatting.pace(selectedCandidate.workout.pace))"
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

        return overlayPoints(from: overlay)
    }

    private func verdictColor(_ verdict: CompareVerdict) -> Color {
        switch verdict.winner {
        case .a: return AppDesign.energeticGreen
        case .b: return AppDesign.alertRed
        case .tie: return .secondary
        }
    }

    private func overlayPoints(from overlay: DistanceOverlay) -> [CompareOverlayPoint] {
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
