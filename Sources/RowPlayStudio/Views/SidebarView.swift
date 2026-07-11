import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var selectedWorkoutID: Int?

    var body: some View {
        let filteredDetails = library.filteredDetails
        return List(selection: $selectedWorkoutID) {
            Section {
                ForEach(filteredDetails) { detail in
                    WorkoutSidebarRow(
                        workout: detail.workout,
                        isPB: library.pbIds.contains(detail.workout.id),
                        distanceUnit: preferences.distanceUnit
                    )
                    .tag(detail.id)
                }
            } header: {
                HStack {
                    Text("\(filteredDetails.count) workouts")
                        .font(AppDesign.Typography.compactLabel)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
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
                            .font(AppDesign.Typography.compactLabel)
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
    var distanceUnit: DistanceUnit

    var body: some View {
        HStack(spacing: AppDesign.Spacing.small) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isPB ? AppDesign.comparisonOrange : Color.clear)
                .frame(width: 3)
                .accessibilityHidden(true)

            Label {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xxSmall) {
                    HStack(spacing: AppDesign.Spacing.small) {
                        Text(workout.workoutType)
                            .lineLimit(1)
                        if isPB {
                            Text("PB")
                                .font(AppDesign.Typography.compactLabel)
                                .foregroundStyle(AppDesign.comparisonOrange)
                                .padding(.horizontal, AppDesign.Spacing.xSmall)
                                .padding(.vertical, 1)
                                .background(AppDesign.comparisonOrange.opacity(0.15), in: Capsule())
                                .accessibilityLabel("Personal Best")
                        }
                    }
                    HStack(spacing: AppDesign.Spacing.xSmall) {
                        Text(workout.date, format: .dateTime.year(.twoDigits).month(.abbreviated).day())
                            .font(AppDesign.Typography.metricLabel)
                        Text("·")
                            .font(AppDesign.Typography.metricLabel)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(RowPlayFormatting.distance(workout.distance, unit: distanceUnit))
                            .font(AppDesign.Typography.metricLabel)
                        Text("·")
                            .font(AppDesign.Typography.metricLabel)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(RowPlayFormatting.time(workout.time))
                            .font(AppDesign.Typography.metricLabel)
                        Text("·")
                            .font(AppDesign.Typography.metricLabel)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(RowPlayFormatting.pace(workout.pace))
                            .font(AppDesign.Typography.metricLabel)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            } icon: {
                Image(systemName: workout.sport.iconName)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(workout.sport.displayName) \(workout.workoutType)\(isPB ? ", Personal Best" : "")"))
        .accessibilityValue(Text("\(workout.date, format: .dateTime.year(.twoDigits).month(.abbreviated).day()); \(RowPlayFormatting.distance(workout.distance, unit: distanceUnit)); \(RowPlayFormatting.time(workout.time)); \(RowPlayFormatting.pace(workout.pace))"))
    }
}
