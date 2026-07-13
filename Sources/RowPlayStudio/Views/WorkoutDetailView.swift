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

    @State private var paceChartDomain: ClosedRange<Double> = -180 ... -60
    @State private var splitBoundaryDistances: [Double] = []

    private var unit: DistanceUnit { preferences.distanceUnit }

    private func chartDistance(_ meters: Double) -> Double {
        unit == .imperial ? meters / 1_609.344 : meters / 1_000
    }

    private var chartDistanceAxisLabel: String {
        unit == .imperial ? "Distance (mi)" : "Distance (km)"
    }

    /// Downsample strokes for chart rendering — caps at ~500 points regardless of
    /// workout length. A 150pt chart can't meaningfully render more detail than this.
    private var chartStrokes: [Stroke] {
        let strokes = detail.strokes
        guard strokes.count > 500 else { return strokes }
        let step = max(strokes.count / 500, 1)
        return stride(from: 0, to: strokes.count, by: step).map { strokes[$0] }
    }

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
            paceChartDomain = Self.computePaceChartDomain(strokes: detail.strokes)
            splitBoundaryDistances = Self.computeSplitBoundaryDistances(
                splits: detail.splits,
                distanceTransform: { unit == .imperial ? $0 / 1_609.344 : $0 / 1_000 }
            )
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
        HStack(alignment: .top, spacing: 0) {
            performanceMetric(
                "Distance",
                RowPlayFormatting.distance(detail.workout.distance, unit: unit),
                color: AppDesign.MetricColor.distance
            )
            metricDivider
            performanceMetric(
                "Time",
                RowPlayFormatting.time(detail.workout.time, tenths: true),
                color: .primary
            )
            metricDivider
            performanceMetric(
                "Avg Pace",
                RowPlayFormatting.pace(detail.workout.pace),
                color: AppDesign.MetricColor.pace
            )
            metricDivider
            performanceMetric(
                "Avg Cadence",
                "\(cadenceText) \(detail.workout.sport.cadenceUnit)",
                color: AppDesign.MetricColor.cadence
            )
            metricDivider
            performanceMetric(
                "Avg Power",
                "\(wattsText) W",
                color: AppDesign.MetricColor.watts
            )
            if let calories = detail.workout.caloriesTotal {
                metricDivider
                performanceMetric("Calories", "\(calories) Cal", color: .primary)
            }
            if let heartRate = detail.workout.heartRateAvg {
                metricDivider
                performanceMetric(
                    "Avg HR",
                    "\(heartRate) bpm",
                    color: AppDesign.MetricColor.heartRate
                )
            }
        }
        .padding(.vertical, AppDesign.Spacing.xLarge)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func performanceMetric(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.small) {
            Text(label.uppercased())
                .font(AppDesign.Typography.metricLabel)
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppDesign.Spacing.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 52)
    }

    @ViewBuilder
    private var strokeChart: some View {
        if detail.strokes.isEmpty {
            ContentUnavailableView("No Stroke Detail", systemImage: "waveform.path.ecg", description: Text("This workout only has summary and split data."))
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xxSmall) {
                    Text("Split Focus")
                        .font(AppDesign.Typography.sectionHeadline)
                    Text(splitFocusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                paceChart
                powerChart

                HStack(spacing: AppDesign.Spacing.xLarge) {
                    chartLegend("Pace", color: AppDesign.MetricColor.pace)
                    chartLegend("Power", color: AppDesign.MetricColor.watts)
                    Spacer()
                    Text(chartDistanceAxisLabel)
                        .font(AppDesign.Typography.metricLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stroke Timeline chart")
            .accessibilityValue(strokeTimelineAccessibilityValue)
            .padding(.vertical, AppDesign.Spacing.xLarge)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var paceChart: some View {
        Chart {
            ForEach(chartStrokes) { stroke in
                LineMark(
                    x: .value("Distance", chartDistance(stroke.d)),
                    y: .value("Pace", -stroke.pace)
                )
                .foregroundStyle(AppDesign.MetricColor.pace)
                .interpolationMethod(.linear)
            }
            splitBoundaryMarks
            RuleMark(y: .value("Average Pace", -detail.workout.pace))
                .foregroundStyle(AppDesign.MetricColor.pace.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartYAxisLabel("Pace (sec/500m)")
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                if let seconds = value.as(Double.self) {
                    AxisValueLabel(RowPlayFormatting.pace(abs(seconds)))
                }
            }
        }
        .chartYScale(domain: paceChartDomain)
        .chartXAxis(.hidden)
        .frame(height: 150)
    }

    private var powerChart: some View {
        Chart {
            ForEach(chartStrokes) { stroke in
                LineMark(
                    x: .value("Distance", chartDistance(stroke.d)),
                    y: .value("Power", stroke.watts)
                )
                .foregroundStyle(AppDesign.MetricColor.watts)
                .interpolationMethod(.linear)
            }
            splitBoundaryMarks
            RuleMark(y: .value("Average Power", strokeSummary.averageWatts))
                .foregroundStyle(AppDesign.MetricColor.watts.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartYAxisLabel("Power (W)")
        .chartXAxisLabel(chartDistanceAxisLabel)
        .frame(height: 150)
    }

    static func computePaceChartDomain(strokes: [Stroke]) -> ClosedRange<Double> {
        let paces = strokes.map(\.pace).filter { $0.isFinite && $0 > 0 }
        guard let fastest = paces.min(), let slowest = paces.max() else {
            return -180 ... -60
        }
        let padding = max((slowest - fastest) * 0.12, 3)
        return -(slowest + padding) ... -(fastest - padding)
    }

    static func computeSplitBoundaryDistances(
        splits: [Split],
        distanceTransform: (Double) -> Double
    ) -> [Double] {
        guard splits.count > 1 else { return [] }
        var cumulative = 0.0
        return splits.dropLast().map { split in
            cumulative += split.distance
            return distanceTransform(cumulative)
        }
    }

    @ChartContentBuilder
    private var splitBoundaryMarks: some ChartContent {
        ForEach(Array(splitBoundaryDistances.enumerated()), id: \.offset) { _, distance in
            RuleMark(x: .value("Split", distance))
                .foregroundStyle(.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func chartLegend(_ label: String, color: Color) -> some View {
        Label {
            Text(label)
        } icon: {
            Capsule()
                .fill(color)
                .frame(width: 18, height: 2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var splitFocusSubtitle: String {
        let splitCount = detail.splits.count
        return splitCount == 1 ? "1 split and finishing effort" : "\(splitCount) splits and finishing effort"
    }

    private var strokeTimelineAccessibilityValue: String {
        "\(strokeSummary.count) strokes, avg pace \(RowPlayFormatting.pace(strokeSummary.averagePace)), avg watts \(Int(strokeSummary.averageWatts))"
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
                    Divider()
                        .gridCellColumns(7)
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
        String(Int(RowPlayFormatting.paceToWatts(for: detail.workout.sport, pacePer500m: split.pace).rounded()))
    }

    private var cadenceText: String {
        detail.workout.strokeRate.map { String(Int($0.rounded())) } ?? "-"
    }

    private var wattsText: String {
        String(Int(RowPlayFormatting.paceToWatts(for: detail.workout.sport, pacePer500m: detail.workout.pace).rounded()))
    }
}
