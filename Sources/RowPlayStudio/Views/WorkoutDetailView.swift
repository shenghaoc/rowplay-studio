import Charts
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct WorkoutDetailView: View {
    var detail: WorkoutDetail
    var summary: DashboardSummary
    var comparisonCandidates: [WorkoutDetail]
    var annotationStore: any AnnotationStore
    var onUpdateDetail: (WorkoutDetail) -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @State private var showingReplay = false

    private var unit: DistanceUnit { preferences.distanceUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricStrip
                replayButton
                WorkoutToolsView(
                    detail: detail,
                    comparisonCandidates: comparisonCandidates,
                    annotationStore: annotationStore,
                    onUpdateDetail: onUpdateDetail
                )
                strokeChart
                splitTable
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(detail.workout.workoutType)
        .navigationDestination(isPresented: $showingReplay) {
            ReplayView(detail: detail)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.workout.workoutType)
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Text(detail.workout.sport.displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
        HStack(spacing: 12) {
            MetricTile(title: "Distance", value: RowPlayFormatting.distance(detail.workout.distance, unit: unit), systemImage: "ruler")
            MetricTile(title: "Time", value: RowPlayFormatting.time(detail.workout.time, tenths: true), systemImage: "timer")
            MetricTile(title: "Pace", value: RowPlayFormatting.pace(detail.workout.pace), systemImage: "speedometer")
            MetricTile(title: "Cadence", value: "\(cadenceText) \(detail.workout.sport.cadenceUnit)", systemImage: "metronome")
            MetricTile(title: "Watts", value: wattsText, systemImage: "bolt")
        }
    }

    @ViewBuilder
    private var replayButton: some View {
        if detail.workout.hasStrokeData {
            Button(action: { showingReplay = true }) {
                Label("Replay Workout", systemImage: "play.rectangle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var strokeChart: some View {
        if detail.strokes.isEmpty {
            ContentUnavailableView("No Stroke Detail", systemImage: "waveform.path.ecg", description: Text("This workout only has summary and split data."))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stroke Timeline")
                    .font(.title3.weight(.semibold))

                Chart(detail.strokes) { stroke in
                    LineMark(
                        x: .value("Time", stroke.t),
                        y: .value("Pace", stroke.pace)
                    )
                    .foregroundStyle(.blue)

                    LineMark(
                        x: .value("Time", stroke.t),
                        y: .value("Watts", Double(stroke.watts))
                    )
                    .foregroundStyle(.orange)
                }
                .chartXAxisLabel("seconds")
                .frame(height: 260)
            }
        }
    }

    private var splitTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.workout.isInterval ? "Intervals" : "Splits")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("#").foregroundStyle(.secondary)
                    Text("Distance").foregroundStyle(.secondary)
                    Text("Time").foregroundStyle(.secondary)
                    Text("Pace").foregroundStyle(.secondary)
                    Text(detail.workout.sport.cadenceUnit).foregroundStyle(.secondary)
                    Text("HR").foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))

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
    }

    private var cadenceText: String {
        detail.workout.strokeRate.map { String(Int($0.rounded())) } ?? "-"
    }

    private var wattsText: String {
        String(Int(RowPlayFormatting.paceToWatts(for: detail.workout.sport, pacePer500m: detail.workout.pace).rounded()))
    }
}
