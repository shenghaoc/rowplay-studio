import RowPlayCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: WorkoutLibrary
    @Binding var selectedWorkoutID: Int?

    var body: some View {
        let filteredDetails = library.filteredDetails
        return List(selection: $selectedWorkoutID) {
            Section {
                ForEach(filteredDetails) { detail in
                    WorkoutSidebarRow(
                        workout: detail.workout,
                        isPB: library.pbIds.contains(detail.workout.id)
                    )
                    .tag(detail.id)
                }
            } header: {
                HStack {
                    Text("\(filteredDetails.count) workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(WorkoutSortField.allCases, id: \.self) { field in
                            Button {
                                toggleSort(field)
                            } label: {
                                HStack {
                                    Text(sortLabel(field))
                                    if library.query.sort == field {
                                        Image(systemName: library.query.dir == .asc ? "arrow.up" : "arrow.down")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .accessibilityLabel("Sort workouts")
                    .help("Sort workouts")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RowPlay")
        .background(clearSelectionButton)
    }

    private var clearSelectionButton: some View {
        Button("") {
            selectedWorkoutID = nil
        }
        .keyboardShortcut(.escape, modifiers: [])
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func toggleSort(_ field: WorkoutSortField) {
        var newQuery = library.query
        if newQuery.sort == field {
            newQuery.dir = newQuery.dir == .asc ? .desc : .asc
        } else {
            newQuery.sort = field
            newQuery.dir = (field == .pace || field == .time) ? .asc : .desc
        }
        library.query = newQuery
    }

    private func sortLabel(_ field: WorkoutSortField) -> String {
        switch field {
        case .date: "Date"
        case .distance: "Distance"
        case .time: "Time"
        case .pace: "Pace"
        case .power: "Power"
        }
    }
}

private struct WorkoutSidebarRow: View {
    var workout: Workout
    var isPB: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workout.workoutType)
                        .lineLimit(1)
                    if isPB {
                        Text("PB")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 4) {
                    Text(workout.date, format: .dateTime.year(.twoDigits).month(.abbreviated).day())
                        .font(.caption)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(RowPlayFormatting.distance(workout.distance))
                        .font(.caption)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(RowPlayFormatting.time(workout.time))
                        .font(.caption)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(RowPlayFormatting.pace(workout.pace))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: workout.sport.iconName)
                .foregroundStyle(.secondary)
        }
    }
}
