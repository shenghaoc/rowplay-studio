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

    @State private var chartCache = WorkoutChartCache.empty

    private var unit: DistanceUnit { preferences.distanceUnit }

    private func chartDistance(_ meters: Double) -> Double {
        unit == .imperial ? meters / 1_609.344 : meters / 1_000
    }

    private var chartDistanceAxisLabel: String {
        unit == .imperial ? "Distance (mi)" : "Distance (km)"
    }

    private var chartCacheIdentity: WorkoutChartCacheIdentity {
        WorkoutChartCacheIdentity(
            detailID: detail.id,
            detailsRevision: detailsRevision,
            distanceUnit: unit.rawValue
        )
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
        .onChange(of: chartCacheIdentity, initial: true) { _, _ in
            refreshChartCache()
        }
    }

    private func refreshChartCache() {
        chartCache = WorkoutChartCache(
            strokes: Self.downsampleStrokes(detail.strokes),
            paceChartDomain: Self.computePaceChartDomain(strokes: detail.strokes),
            splitBoundaryDistances: Self.computeSplitBoundaryDistances(
                splits: detail.splits,
                distanceTransform: { unit == .imperial ? $0 / 1_609.344 : $0 / 1_000 }
            )
        )
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
                "Avg Pace",
                RowPlayFormatting.pace(detail.workout.pace),
                color: AppDesign.MetricColor.pace
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

    private func performanceMetric(_ label: String, _ value: String, color: Color) -> some View {
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
        .accessibilityLabel(label)
        .accessibilityValue(value)
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
        }
    }

    private var paceChart: some View {
        Chart {
            ForEach(chartCache.strokes) { stroke in
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
        .chartYScale(domain: chartCache.paceChartDomain)
        .chartXAxis(.hidden)
        .frame(height: AppDesign.Chart.strokeHeight)
    }

    private var powerChart: some View {
        Chart {
            ForEach(chartCache.strokes) { stroke in
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
        .frame(height: AppDesign.Chart.strokeHeight)
    }

    static func computePaceChartDomain(strokes: [Stroke]) -> ClosedRange<Double> {
        let paces = strokes.map(\.pace).filter { $0.isFinite && $0 > 0 }
        guard let fastest = paces.min(), let slowest = paces.max() else {
            return -180 ... -60
        }
        let padding = max((slowest - fastest) * 0.12, 3)
        return -(slowest + padding) ... -(fastest - padding)
    }

    /// Produces a bounded chart sample while retaining both workout endpoints.
    static func downsampleStrokes(_ strokes: [Stroke], limit: Int = 500) -> [Stroke] {
        guard limit > 0 else { return [] }
        guard strokes.count > limit else { return strokes }
        guard limit > 1 else { return [strokes[0]] }

        let lastIndex = strokes.count - 1
        return (0..<limit).map { sampleIndex in
            let strokeIndex = sampleIndex * lastIndex / (limit - 1)
            return strokes[strokeIndex]
        }
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
        ForEach(Array(chartCache.splitBoundaryDistances.enumerated()), id: \.offset) { _, distance in
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

private struct WorkoutChartCache {
    var strokes: [Stroke]
    var paceChartDomain: ClosedRange<Double>
    var splitBoundaryDistances: [Double]

    static let empty = WorkoutChartCache(
        strokes: [],
        paceChartDomain: -180 ... -60,
        splitBoundaryDistances: []
    )
}

private struct WorkoutChartCacheIdentity: Equatable {
    var detailID: Int
    var detailsRevision: UInt64
    var distanceUnit: String
}
