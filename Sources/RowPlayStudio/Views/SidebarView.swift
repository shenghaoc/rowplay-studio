import RowPlayCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: WorkoutLibrary
    @Binding var selectedWorkoutID: Int?

    var body: some View {
        List(selection: $selectedWorkoutID) {
            Section("Workouts") {
                ForEach(library.filteredDetails) { detail in
                    WorkoutSidebarRow(workout: detail.workout)
                        .tag(detail.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RowPlay")
    }
}

private struct WorkoutSidebarRow: View {
    var workout: Workout

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutType)
                    .lineLimit(1)
                Text("\(workout.sport.displayName) - \(RowPlayFormatting.distance(workout.distance)) - \(RowPlayFormatting.time(workout.time))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch workout.sport {
        case .rower:
            "figure.rower"
        case .skierg:
            "figure.skiing.crosscountry"
        case .bike:
            "bicycle"
        }
    }
}

