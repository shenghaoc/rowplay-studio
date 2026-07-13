import Charts
import RowPlayCore
import SwiftUI

/// Focused stroke-analysis surface for workout detail.
///
/// Expensive stroke derivations are refreshed only when the selected workout,
/// detail revision, or distance unit changes.
struct WorkoutStrokeAnalysisView: View {
    var detail: WorkoutDetail
    var detailsRevision: UInt64
    var strokeSummary: StrokeSummary
    var unit: DistanceUnit

    @State private var chartCache = WorkoutStrokeChartCache.empty

    private var cacheIdentity: WorkoutStrokeChartCacheIdentity {
        WorkoutStrokeChartCacheIdentity(
            detailID: detail.id,
            detailsRevision: detailsRevision,
            distanceUnit: unit
        )
    }

    var body: some View {
        Group {
            if detail.strokes.isEmpty {
                ContentUnavailableView(
                    "No Stroke Detail",
                    systemImage: "waveform.path.ecg",
                    description: Text("This workout only has summary and split data.")
                )
            } else {
                charts
            }
        }
        .onChange(of: cacheIdentity, initial: true) { _, _ in
            refreshChartCache()
        }
    }

    private var charts: some View {
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
                Text(distanceAxisLabel)
                    .font(AppDesign.Typography.metricLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stroke Timeline chart")
        .accessibilityValue(strokeTimelineAccessibilityValue)
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
        .chartXAxisLabel(distanceAxisLabel)
        .frame(height: AppDesign.Chart.strokeHeight)
    }

    @ChartContentBuilder
    private var splitBoundaryMarks: some ChartContent {
        ForEach(Array(chartCache.splitBoundaryDistances.enumerated()), id: \.offset) { _, distance in
            RuleMark(x: .value("Split", distance))
                .foregroundStyle(.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func refreshChartCache() {
        chartCache = WorkoutStrokeChartCache(
            strokes: Self.downsampleStrokes(detail.strokes),
            paceChartDomain: Self.computePaceChartDomain(strokes: detail.strokes),
            splitBoundaryDistances: Self.computeSplitBoundaryDistances(
                splits: detail.splits,
                distanceTransform: chartDistance
            )
        )
    }

    private func chartDistance(_ meters: Double) -> Double {
        unit == .imperial ? meters / 1_609.344 : meters / 1_000
    }

    private var distanceAxisLabel: String {
        unit == .imperial ? "Distance (mi)" : "Distance (km)"
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
}

private struct WorkoutStrokeChartCache {
    var strokes: [Stroke]
    var paceChartDomain: ClosedRange<Double>
    var splitBoundaryDistances: [Double]

    static let empty = WorkoutStrokeChartCache(
        strokes: [],
        paceChartDomain: -180 ... -60,
        splitBoundaryDistances: []
    )
}

private struct WorkoutStrokeChartCacheIdentity: Equatable {
    var detailID: Int
    var detailsRevision: UInt64
    var distanceUnit: DistanceUnit
}
