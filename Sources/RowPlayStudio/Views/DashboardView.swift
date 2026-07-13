import Charts
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct DashboardView: View {
    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    var summary: DashboardSummary
    var personalBests: [DashboardPersonalBest]
    var recentPaceWorkouts: [Workout]

    private var unit: DistanceUnit { preferences.distanceUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xxxLarge) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))

                LiveModePanelView(library: library)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: AppDesign.Spacing.large) {
                    MetricTile(title: "Sessions", value: "\(summary.sessions)", systemImage: "calendar")
                    MetricTile(title: "Distance", value: RowPlayFormatting.distance(summary.totalDistance, unit: unit), systemImage: "point.topleft.down.curvedto.point.bottomright.up", color: AppDesign.MetricColor.distance)
                    MetricTile(title: "Challenge", value: RowPlayFormatting.distance(summary.challengeDistance, unit: unit), systemImage: "flag.checkered", color: AppDesign.MetricColor.distance)
                    MetricTile(title: "Time", value: RowPlayFormatting.time(summary.totalTime), systemImage: "clock", color: AppDesign.MetricColor.duration)
                    MetricTile(title: "Avg Pace", value: RowPlayFormatting.pace(summary.averagePace), systemImage: "speedometer", color: AppDesign.MetricColor.pace)
                }

                personalBestsSection

                sportSummarySection

                distanceBySportChart
                recentPaceChart
            }
            .padding(AppDesign.Spacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Charts

    private var distanceBySportChart: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text("Distance by Sport")
                .font(AppDesign.Typography.sectionHeadline)

            Chart(summary.bySport) { item in
                BarMark(
                    x: .value("Sport", item.sport.displayName),
                    y: .value("Distance", unit == .imperial ? item.distance / 1_609.344 : item.distance / 1_000)
                )
                .foregroundStyle(by: .value("Sport", item.sport.displayName))
            }
            .chartYAxisLabel(unit == .imperial ? "mi" : "km")
            .frame(height: 220)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Distance by Sport chart")
        .accessibilityValue(distanceBySportAccessibilityValue)
        .panelStyle()
    }

    private var distanceBySportAccessibilityValue: String {
        summary.bySport.map { item in
            "\(item.sport.displayName): \(RowPlayFormatting.distance(item.distance, unit: unit))"
        }.joined(separator: ", ")
    }

    private var recentPaceChart: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text("Recent Pace")
                .font(AppDesign.Typography.sectionHeadline)

            Chart(recentPaceWorkouts) { workout in
                LineMark(
                    x: .value("Date", workout.date),
                    y: .value("Pace", -workout.pace)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppDesign.MetricColor.pace)

                PointMark(
                    x: .value("Date", workout.date),
                    y: .value("Pace", -workout.pace)
                )
                .foregroundStyle(AppDesign.MetricColor.pace)
                .symbolSize(28)
            }
            .chartYAxisLabel("Pace (/500m)")
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel(RowPlayFormatting.pace(abs(seconds)))
                    }
                }
            }
            .chartYScale(domain: recentPaceChartDomain)
            .frame(height: 220)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent Pace chart")
        .accessibilityValue(recentPaceAccessibilityValue)
        .panelStyle()
    }

    private var recentPaceAccessibilityValue: String {
        guard !recentPaceWorkouts.isEmpty else { return "No data" }
        let paces = recentPaceWorkouts.map { RowPlayFormatting.pace($0.pace) }
        return "\(recentPaceWorkouts.count) workouts, paces: \(paces.joined(separator: ", "))"
    }

    private var recentPaceChartDomain: ClosedRange<Double> {
        let paces = recentPaceWorkouts.map(\.pace).filter { $0.isFinite && $0 > 0 }
        guard let fastest = paces.min(), let slowest = paces.max() else {
            return -180 ... -60
        }
        let padding = max((slowest - fastest) * 0.12, 3)
        return -(slowest + padding) ... -(fastest - padding)
    }

    // MARK: - Personal Bests

    @ViewBuilder
    private var personalBestsSection: some View {
        if !personalBests.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
                Text("Personal Bests")
                    .font(AppDesign.Typography.sectionHeadline)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: AppDesign.Spacing.medium) {
                    ForEach(personalBests) { pb in
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.xSmall) {
                            HStack(spacing: AppDesign.Spacing.small) {
                                Image(systemName: pb.sport.iconName)
                                    .foregroundStyle(.secondary)
                                Text(pbLabel(pb.distance))
                                Text(pb.sport.displayName)
                                    .foregroundStyle(.secondary)
                            }
                            .font(AppDesign.Typography.compactLabel)
                            Text(RowPlayFormatting.time(pb.time, tenths: true))
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AppDesign.MetricColor.duration)
                            Text(RowPlayFormatting.pace(pb.pace))
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(AppDesign.MetricColor.pace)
                            Text(pb.date, format: .dateTime.year().month(.abbreviated).day())
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppDesign.Spacing.medium)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.small))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(pbLabel(pb.distance) == "Half" ? "Half Marathon" : (pbLabel(pb.distance) == "Marathon" ? "Marathon" : Measurement(value: pb.distance, unit: UnitLength.meters).formatted(.measurement(width: .wide)))) \(pb.sport.displayName) Personal Best")
                        .accessibilityValue("\(Duration.seconds(pb.time).formatted(.units(width: .wide, fractionalPart: .show(length: 1)))), \(Duration.seconds(pb.pace).formatted(.units(width: .wide, fractionalPart: .show(length: 1)))) per 500 meters, \(pb.date, format: .dateTime.year().month(.abbreviated).day())")
                    }
                }
            }
        }
    }

    private func pbLabel(_ distance: Double) -> String {
        if abs(distance - 21_097) < 10 {
            return "Half"
        }
        if abs(distance - 42_195) < 10 {
            return "Marathon"
        }
        if distance >= 1_000 {
            return "\(Int(distance / 1_000))k"
        }
        return "\(Int(distance))m"
    }

    // MARK: - Sport Summary

    @ViewBuilder
    private var sportSummarySection: some View {
        if !summary.bySport.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
                Text("By Sport")
                    .font(AppDesign.Typography.sectionHeadline)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: AppDesign.Spacing.large) {
                    ForEach(summary.bySport) { sport in
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.small) {
                            HStack(spacing: AppDesign.Spacing.small) {
                                Image(systemName: sport.sport.iconName)
                                    .foregroundStyle(.secondary)
                                Text(sport.sport.displayName)
                                    .font(.headline)
                            }
                            Text("\(sport.sessions) sessions")
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(.secondary)
                            Text(RowPlayFormatting.distance(sport.distance, unit: unit))
                                .font(AppDesign.Typography.metricValue.monospacedDigit())
                                .foregroundStyle(AppDesign.MetricColor.distance)
                            Text("Best: \(RowPlayFormatting.pace(sport.bestPace))")
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(AppDesign.MetricColor.pace)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppDesign.Spacing.large)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(sport.sport.displayName) Summary")
                        .accessibilityValue(Self.sportSummaryAccessibilityValue(sport, unit: unit))
                    }
                }
            }
        }
    }

    static func sportSummaryAccessibilityValue(_ sport: SportSummary, unit: DistanceUnit) -> String {
        "\(sport.sessions) sessions, \(RowPlayFormatting.distance(sport.distance, unit: unit)), Best Pace: \(Duration.seconds(sport.bestPace).formatted(.units(width: .wide, fractionalPart: .show(length: 1)))) per 500 meters"
    }
}
