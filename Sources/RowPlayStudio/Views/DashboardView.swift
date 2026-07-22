import Charts
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct DashboardView: View {
    private static let dateFormatStyle = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(.autoupdatingCurrent)
    private static let measurementFormatStyle = Measurement<UnitLength>.FormatStyle.measurement(width: .wide).locale(.autoupdatingCurrent)
    private static let durationFormatStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.hours, .minutes, .seconds],
        width: .wide,
        fractionalPart: .show(length: 1)
    ).locale(.autoupdatingCurrent)

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
                    .font(AppDesign.Typography.pageTitle)

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

                distanceBySportChart
                recentPaceChart
            }
            .padding(AppDesign.Spacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var distanceBySportAccessibilityValue: String {
        Self.distanceBySportAccessibilityDescription(summary.bySport, unit: unit)
    }

    private var recentPaceAccessibilityValue: String {
        Self.recentPaceAccessibilityDescription(recentPaceWorkouts)
    }

    private var recentPaceChartDomain: ClosedRange<Double> {
        Self.recentPaceChartDomain(for: recentPaceWorkouts)
    }

    static func distanceBySportAccessibilityDescription(
        _ summaries: [SportSummary],
        unit: DistanceUnit
    ) -> String {
        summaries.map { item in
            "\(item.sport.displayName): \(RowPlayFormatting.distance(item.distance, unit: unit))"
        }.joined(separator: ", ")
    }

    static func recentPaceAccessibilityDescription(_ workouts: [Workout]) -> String {
        guard !workouts.isEmpty else { return "No data" }
        let paces = workouts.map { RowPlayFormatting.pace($0.pace) }
        return "\(workouts.count) workouts, paces: \(paces.joined(separator: ", "))"
    }

    static func recentPaceChartDomain(for workouts: [Workout]) -> ClosedRange<Double> {
        let paces = workouts.map(\.pace).filter { $0.isFinite && $0 > 0 }
        if let fastest = paces.min(), let slowest = paces.max() {
            let padding = max((slowest - fastest) * 0.12, 3)
            return -(slowest + padding) ... -(fastest - padding)
        }
        return -180 ... -60
    }

    // MARK: - Charts

    private var distanceBySportChart: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            Text("By Sport")
                .font(AppDesign.Typography.sectionHeadline)

            Chart(summary.bySport) { item in
                BarMark(
                    x: .value("Sport", item.sport.displayName),
                    y: .value("Distance", unit == .imperial ? item.distance / 1_609.344 : item.distance / 1_000)
                )
                .foregroundStyle(by: .value("Sport", item.sport.displayName))
            }
            .chartYAxisLabel(unit == .imperial ? "mi" : "km")
            .frame(height: AppDesign.Chart.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Distance by Sport chart")
        .accessibilityValue(distanceBySportAccessibilityValue)
        .panelStyle()
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
            .frame(height: AppDesign.Chart.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent Pace chart")
        .accessibilityValue(recentPaceAccessibilityValue)
        .panelStyle()
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
                            Text(pb.date, format: Self.dateFormatStyle)
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppDesign.Spacing.medium)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.small))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(pbAccessibilityLabel(pb))
                        .accessibilityValue(pbAccessibilityValue(pb))
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

    private func pbAccessibilityLabel(_ pb: DashboardPersonalBest) -> String {
        let label = pbLabel(pb.distance)
        let distanceText: String
        if label == "Half" {
            distanceText = "Half Marathon"
        } else if label == "Marathon" {
            distanceText = "Marathon"
        } else {
            distanceText = Measurement(value: pb.distance, unit: UnitLength.meters)
                .formatted(Self.measurementFormatStyle)
        }
        return "\(distanceText) \(pb.sport.displayName) Personal Best"
    }

    private func pbAccessibilityValue(_ pb: DashboardPersonalBest) -> String {
        let timeFormatted = Duration.seconds(pb.time).formatted(Self.durationFormatStyle)
        let paceFormatted = Duration.seconds(pb.pace).formatted(Self.durationFormatStyle)
        let dateFormatted = pb.date.formatted(Self.dateFormatStyle)
        return "\(timeFormatted), \(paceFormatted) per 500 meters, \(dateFormatted)"
    }
}
