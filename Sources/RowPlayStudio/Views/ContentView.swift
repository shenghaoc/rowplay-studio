import RowPlayCore
import SwiftUI

struct ContentView: View {
    private static let dashboardSelectionID = -1

    @ObservedObject var library: WorkoutLibrary
    @SceneStorage("selectedWorkoutID") private var storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID

    var body: some View {
        NavigationSplitView {
            SidebarView(
                library: library,
                selectedWorkoutID: selectionBinding
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let selectedWorkoutID, let detail = library.detail(id: selectedWorkoutID) {
                WorkoutDetailView(detail: detail, summary: library.summary)
            } else {
                DashboardView(
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
                    library.reloadDemoData()
                    storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
                } label: {
                    Label("Reload Demo Library", systemImage: "arrow.clockwise")
                }
            }
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
