import RowPlayCore
import SwiftUI

struct ContentView: View {
    private static let dashboardSelectionID = -1

    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    @SceneStorage("selectedWorkoutID") private var storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID

    var body: some View {
        NavigationSplitView {
            SidebarView(
                library: library,
                selectedWorkoutID: selectionBinding
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if library.isEmpty && !preferences.demoModeEnabled {
                emptyState
            } else if let selectedWorkoutID, let detail = library.detail(id: selectedWorkoutID) {
                WorkoutDetailView(
                    detail: detail,
                    summary: library.summary,
                    comparisonCandidates: library.comparisonCandidates(for: detail.id),
                    annotationStore: library.annotationStore,
                    onUpdateDetail: library.updateDetail
                )
            } else {
                DashboardView(
                    library: library,
                    summary: library.filteredSummary,
                    workouts: library.filteredWorkouts,
                    pbIds: library.pbIds
                )
            }
        }
        .searchable(text: searchTextBinding, placement: .sidebar)
        .toolbar {
            ToolbarItemGroup {
                Picker("Sport", selection: sportBinding) {
                    Text("All").tag(Sport?.none)
                    ForEach(Sport.allCases) { sport in
                        Text(sport.displayName).tag(Sport?.some(sport))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button {
                    guard preferences.demoModeEnabled else { return }
                    library.reloadDemoData()
                    storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
                } label: {
                    Label("Reload Demo Library", systemImage: "arrow.clockwise")
                }
                .disabled(!preferences.demoModeEnabled)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workouts", systemImage: "figure.rower")
        } description: {
            Text("Enable Demo Mode in Settings to explore sample workouts, or add real workout data.")
        }
    }

    private var selectedWorkoutID: Int? {
        storedSelectedWorkoutID == Self.dashboardSelectionID ? nil : storedSelectedWorkoutID
    }

    private var selectionBinding: Binding<Int?> {
        Binding {
            selectedWorkoutID
        } set: { newValue in
            storedSelectedWorkoutID = newValue ?? Self.dashboardSelectionID
        }
    }

    private var sportBinding: Binding<Sport?> {
        Binding {
            library.query.sport
        } set: { newValue in
            library.query.sport = newValue
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            library.query.searchText ?? ""
        } set: { newValue in
            library.query.searchText = newValue.isEmpty ? nil : newValue
        }
    }
}
