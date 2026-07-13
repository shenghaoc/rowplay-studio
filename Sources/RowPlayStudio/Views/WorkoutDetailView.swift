import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct WorkoutDetailView: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var strokeSummary: StrokeSummary
    var comparisonCandidates: [WorkoutDetail]
    var annotationStore: any AnnotationStore
    var onUpdateDetail: (WorkoutDetail) -> Void
    var onReplay: () -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.automationModeEnabled) private var automationModeEnabled
    @State private var areToolsExpanded = false

    private var unit: DistanceUnit { preferences.distanceUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xxxLarge) {
                header
                metricStrip
                strokeChart
                splitTable
                toolSection
            }
            .padding(AppDesign.Spacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(detail.workout.workoutType)
        .toolbar {
            if detail.workout.hasStrokeData {
                ToolbarItem {
                    Button(action: onReplay) {
                        Label("Replay Workout", systemImage: "play.rectangle.fill")
                    }
                    .help("Replay workout with stroke data")
                    .accessibilityHint("Opens the workout replay viewer")
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
        }
        .onAppear {
            if automationModeEnabled {
                areToolsExpanded = true
            }
        }
    }

    private var toolSection: some View {
        DisclosureGroup(isExpanded: $areToolsExpanded) {
            WorkoutToolsView(
                detail: detail,
                detailsRevision: detailsRevision,
                comparisonCandidates: comparisonCandidates,
                annotationStore: annotationStore,
                onUpdateDetail: onUpdateDetail
            )
            .padding(.top, AppDesign.Spacing.medium)
        } label: {
            Text("Workout Tools")
                .font(AppDesign.Typography.sectionHeadline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.workout.workoutType)
                    .font(AppDesign.Typography.pageTitle)
                Spacer()
                Text(detail.workout.sport.displayName)
                    .font(AppDesign.Typography.sectionHeadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AppDesign.Spacing.medium) {
                Text(detail.workout.date, style: .date)
                Text(detail.workout.date, style: .time)
                if let source = detail.workout.source {
                    Text(source)
                }
                if detail.workout.isInterval {
                    Text("Intervals")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let comments = detail.workout.comments {
                Text(comments)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            performanceMetric(
                "Distance",
                RowPlayFormatting.distance(detail.workout.distance, unit: unit),
                color: AppDesign.MetricColor.distance
            )
            performanceMetric(
                "Time",
                RowPlayFormatting.time(detail.workout.time, tenths: true),
                color: .primary
            )
            performanceMetric(
                "Pace /500m",
                RowPlayFormatting.time(detail.workout.pace, tenths: true),
                color: AppDesign.MetricColor.pace,
                accessibilityLabel: "Average Pace",
                accessibilityValue: RowPlayFormatting.pace(detail.workout.pace)
            )
            performanceMetric(
                "Avg Cadence",
                "\(cadenceText) \(detail.workout.sport.cadenceUnit)",
                color: AppDesign.MetricColor.cadence
            )
            performanceMetric(
                "Avg Power",
                "\(wattsText) W",
                color: AppDesign.MetricColor.watts
            )
            if let calories = detail.workout.caloriesTotal {
                performanceMetric("Calories", "\(calories) Cal", color: .primary)
            }
            if let heartRate = detail.workout.heartRateAvg {
                performanceMetric(
                    "Avg HR",
                    "\(heartRate) bpm",
                    color: AppDesign.MetricColor.heartRate
                )
            }
        }
        .padding(.vertical, AppDesign.Spacing.large)
    }

    private func performanceMetric(
        _ label: String,
        _ value: String,
        color: Color,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.small) {
            Text(label.uppercased())
                .font(AppDesign.Typography.metricLabel)
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppDesign.Typography.stripMetric)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppDesign.Spacing.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityValue(accessibilityValue ?? value)
    }

    private var strokeChart: some View {
        WorkoutStrokeAnalysisView(
            detail: detail,
            detailsRevision: detailsRevision,
            strokeSummary: strokeSummary,
            unit: unit
        )
    }

    private var splitTable: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text(detail.workout.isInterval ? "Intervals" : "Splits")
                .font(AppDesign.Typography.sectionHeadline)

            Grid(alignment: .leading, horizontalSpacing: AppDesign.Spacing.xxxLarge, verticalSpacing: AppDesign.Spacing.large) {
                GridRow {
                    tableHeader("Split")
                    tableHeader("Distance")
                    tableHeader("Time")
                    tableHeader("Pace (/500m)")
                    tableHeader(detail.workout.sport.cadenceUnit)
                    tableHeader("Power (W)")
                    tableHeader("HR")
                }

                ForEach(detail.splits) { split in
                    GridRow {
                        Text("\(split.index)")
                        Text(RowPlayFormatting.distance(split.distance, unit: unit))
                        Text(RowPlayFormatting.time(split.time, tenths: true))
                        Text(RowPlayFormatting.pace(split.pace))
                            .foregroundStyle(AppDesign.MetricColor.pace)
                        Text(split.cadence.map { String(Int($0.rounded())) } ?? "-")
                            .foregroundStyle(AppDesign.MetricColor.cadence)
                        Text(splitPower(split))
                            .foregroundStyle(AppDesign.MetricColor.watts)
                        Text(split.heartRate?.average.map(String.init) ?? "-")
                    }
                    .monospacedDigit()
                }
            }
            .font(.callout)
        }
        .padding(.vertical, AppDesign.Spacing.xLarge)
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppDesign.Typography.metricLabel)
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    private func splitPower(_ split: Split) -> String {
        Self.powerText(for: detail.workout.sport, pace: split.pace)
    }

    private var cadenceText: String {
        detail.workout.strokeRate.map { String(Int($0.rounded())) } ?? "-"
    }

    private var wattsText: String {
        Self.powerText(for: detail.workout.sport, pace: detail.workout.pace)
    }

    static func powerText(for sport: Sport, pace: TimeInterval) -> String {
        guard pace.isFinite, pace > 0 else { return "-" }
        let watts = RowPlayFormatting.paceToWatts(for: sport, pacePer500m: pace)
        guard watts.isFinite, watts >= 0, watts <= Double(Int.max) else { return "-" }
        return String(Int(watts.rounded()))
    }
}
