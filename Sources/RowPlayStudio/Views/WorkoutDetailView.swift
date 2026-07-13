import Charts
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct WorkoutDetailView: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var strokeSummary: StrokeSummary
    var summary: DashboardSummary
    var comparisonCandidates: [WorkoutDetail]
    var annotationStore: any AnnotationStore
    var onUpdateDetail: (WorkoutDetail) -> Void
    var onReplay: () -> Void
    @EnvironmentObject private var preferences: AppPreferences

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
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
        }
    }

    private var toolSection: some View {
        DisclosureGroup {
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
                    .font(.largeTitle.weight(.semibold))
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
        HStack(spacing: AppDesign.Spacing.large) {
            MetricTile(title: "Distance", value: RowPlayFormatting.distance(detail.workout.distance, unit: unit), systemImage: "ruler", color: AppDesign.MetricColor.distance)
            MetricTile(title: "Time", value: RowPlayFormatting.time(detail.workout.time, tenths: true), systemImage: "timer", color: AppDesign.MetricColor.duration)
            MetricTile(title: "Pace", value: RowPlayFormatting.pace(detail.workout.pace), systemImage: "speedometer", color: AppDesign.MetricColor.pace)
            MetricTile(title: "Cadence", value: "\(cadenceText) \(detail.workout.sport.cadenceUnit)", systemImage: "metronome", color: AppDesign.MetricColor.cadence)
            MetricTile(title: "Watts", value: wattsText, systemImage: "bolt", color: AppDesign.MetricColor.watts)
        }
    }

    @ViewBuilder
    private var strokeChart: some View {
        if detail.strokes.isEmpty {
            ContentUnavailableView("No Stroke Detail", systemImage: "waveform.path.ecg", description: Text("This workout only has summary and split data."))
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
                Text("Stroke Timeline")
                    .font(AppDesign.Typography.sectionHeadline)

                Chart(detail.strokes) { stroke in
                    LineMark(
                        x: .value("Time", stroke.t),
                        y: .value("Pace", stroke.pace)
                    )
                    .foregroundStyle(by: .value("Metric", "Pace"))

                    LineMark(
                        x: .value("Time", stroke.t),
                        y: .value("Watts", Double(stroke.watts))
                    )
                    .foregroundStyle(by: .value("Metric", "Watts"))
                }
                .chartForegroundStyleScale([
                    "Pace": AppDesign.MetricColor.pace,
                    "Watts": AppDesign.MetricColor.watts
                ])
                .chartXAxisLabel("seconds")
                .frame(height: 260)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stroke Timeline chart")
            .accessibilityValue(strokeTimelineAccessibilityValue)
            .padding(AppDesign.Spacing.xLarge)
            .background(AppDesign.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
        }
    }

    private var strokeTimelineAccessibilityValue: String {
        "\(strokeSummary.count) strokes, avg pace \(RowPlayFormatting.pace(strokeSummary.averagePace)), avg watts \(Int(strokeSummary.averageWatts))"
    }

    private var splitTable: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text(detail.workout.isInterval ? "Intervals" : "Splits")
                .font(AppDesign.Typography.sectionHeadline)

            Grid(alignment: .leading, horizontalSpacing: AppDesign.Spacing.xxxLarge, verticalSpacing: AppDesign.Spacing.medium) {
                GridRow {
                    Text("#").foregroundStyle(.secondary)
                    Text("Distance").foregroundStyle(.secondary)
                    Text("Time").foregroundStyle(.secondary)
                    Text("Pace").foregroundStyle(.secondary)
                    Text(detail.workout.sport.cadenceUnit).foregroundStyle(.secondary)
                    Text("HR").foregroundStyle(.secondary)
                }
                .font(AppDesign.Typography.compactLabel)

                ForEach(detail.splits) { split in
                    GridRow {
                        Text("\(split.index)")
                        Text(RowPlayFormatting.distance(split.distance, unit: unit))
                        Text(RowPlayFormatting.time(split.time, tenths: true))
                        Text(RowPlayFormatting.pace(split.pace))
                        Text(split.cadence.map { String(Int($0.rounded())) } ?? "-")
                        Text(split.heartRate?.average.map(String.init) ?? "-")
                    }
                    Divider()
                        .gridCellColumns(6)
                }
            }
            .font(.callout)
        }
        .padding(AppDesign.Spacing.xLarge)
        .background(AppDesign.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
    }

    private var cadenceText: String {
        detail.workout.strokeRate.map { String(Int($0.rounded())) } ?? "-"
    }

    private var wattsText: String {
        String(Int(RowPlayFormatting.paceToWatts(for: detail.workout.sport, pacePer500m: detail.workout.pace).rounded()))
    }
}
