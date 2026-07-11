import Charts
import RowPlayCore
import RowPlayMacOS
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
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))

                LiveModePanelView(library: library)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 220))
                ], spacing: 12) {
                    MetricTile(title: "Sessions", value: "\(summary.sessions)", systemImage: "calendar")
                    MetricTile(title: "Distance", value: RowPlayFormatting.distance(summary.totalDistance, unit: unit), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    MetricTile(title: "Challenge", value: RowPlayFormatting.distance(summary.challengeDistance, unit: unit), systemImage: "flag.checkered")
                    MetricTile(title: "Time", value: RowPlayFormatting.time(summary.totalTime), systemImage: "clock")
                    MetricTile(title: "Avg Pace", value: RowPlayFormatting.pace(summary.averagePace), systemImage: "speedometer")
                }

                personalBestsSection

                sportSummarySection

                VStack(alignment: .leading, spacing: 12) {
                    Text("Distance by Sport")
                        .font(.title3.weight(.semibold))

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Pace")
                        .font(.title3.weight(.semibold))

                    Chart(recentPaceWorkouts) { workout in
                        LineMark(
                            x: .value("Date", workout.date),
                            y: .value("Pace", workout.pace)
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", workout.date),
                            y: .value("Pace", workout.pace)
                        )
                    }
                    .chartYAxisLabel("sec/500m")
                    .frame(height: 220)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Personal Bests

    @ViewBuilder
    private var personalBestsSection: some View {
        if !personalBests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal Bests")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: 10) {
                    ForEach(personalBests) { pb in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: pb.sport.iconName)
                                    .foregroundStyle(.secondary)
                                Text(pbLabel(pb.distance))
                                Text(pb.sport.displayName)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            Text(RowPlayFormatting.time(pb.time, tenths: true))
                                .font(.title3.monospacedDigit().weight(.semibold))
                            Text(RowPlayFormatting.pace(pb.pace))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pb.date, format: .dateTime.year().month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            VStack(alignment: .leading, spacing: 12) {
                Text("By Sport")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: 12) {
                    ForEach(summary.bySport) { sport in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: sport.sport.iconName)
                                    .foregroundStyle(.secondary)
                                Text(sport.sport.displayName)
                                    .font(.headline)
                            }
                            Text("\(sport.sessions) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(RowPlayFormatting.distance(sport.distance, unit: unit))
                                .font(.subheadline.monospacedDigit())
                            Text("Best: \(RowPlayFormatting.pace(sport.bestPace))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
