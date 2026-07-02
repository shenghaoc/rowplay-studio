import Charts
import RowPlayCore
import SwiftUI

struct DashboardView: View {
    var summary: DashboardSummary
    var workouts: [Workout]
    var pbIds: Set<Int>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 220))
                ], spacing: 12) {
                    MetricTile(title: "Sessions", value: "\(summary.sessions)", systemImage: "calendar")
                    MetricTile(title: "Distance", value: RowPlayFormatting.distance(summary.totalDistance), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    MetricTile(title: "Challenge", value: RowPlayFormatting.distance(summary.challengeDistance), systemImage: "flag.checkered")
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
                            y: .value("Distance", item.distance / 1_000)
                        )
                        .foregroundStyle(by: .value("Sport", item.sport.displayName))
                    }
                    .chartYAxisLabel("km")
                    .frame(height: 220)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Pace")
                        .font(.title3.weight(.semibold))

                    Chart(recentRowerPieces) { workout in
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
        let pbs = WorkoutAnalytics.dashboardPersonalBests(for: workouts, pbIds: pbIds)
        if !pbs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal Bests")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240))
                ], spacing: 10) {
                    ForEach(pbs) { pb in
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
                    }
                }
            }
        }
    }

    private func pbLabel(_ distance: Double) -> String {
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
                            Text(RowPlayFormatting.distance(sport.distance))
                                .font(.subheadline.monospacedDigit())
                            Text("Best: \(RowPlayFormatting.pace(sport.bestPace))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var recentRowerPieces: [Workout] {
        // Use the active sport filter if set; otherwise default to the sport with the most workouts.
        let sport: Sport = {
            let sports = Set(workouts.map(\.sport))
            if sports.count == 1, let only = sports.first { return only }
            return Dictionary(grouping: workouts, by: \.sport)
                .max(by: { $0.value.count < $1.value.count })?.key ?? .rower
        }()
        return WorkoutAnalytics.recentPaceWorkouts(for: workouts, sport: sport, limit: 10)
    }
}
