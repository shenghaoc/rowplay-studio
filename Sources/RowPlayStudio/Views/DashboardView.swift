import Charts
import RowPlayCore
import SwiftUI

struct DashboardView: View {
    var summary: DashboardSummary
    var details: [WorkoutDetail]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))

                HStack(spacing: 12) {
                    MetricTile(title: "Sessions", value: "\(summary.sessions)", systemImage: "calendar")
                    MetricTile(title: "Distance", value: RowPlayFormatting.distance(summary.totalDistance), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    MetricTile(title: "Time", value: RowPlayFormatting.time(summary.totalTime), systemImage: "clock")
                    MetricTile(title: "Avg Pace", value: RowPlayFormatting.pace(summary.averagePace), systemImage: "speedometer")
                }

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

                    Chart(recentRowerPieces) { detail in
                        LineMark(
                            x: .value("Date", detail.workout.date),
                            y: .value("Pace", detail.workout.pace)
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", detail.workout.date),
                            y: .value("Pace", detail.workout.pace)
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

    private var recentRowerPieces: [WorkoutDetail] {
        details
            .filter { $0.workout.sport == .rower }
            .sorted { $0.workout.date < $1.workout.date }
            .suffix(10)
    }
}

