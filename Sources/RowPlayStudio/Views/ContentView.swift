import RowPlayCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var library: WorkoutLibrary
    @SceneStorage("selectedWorkoutID") private var selectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID

    var body: some View {
        NavigationSplitView {
            SidebarView(
                library: library,
                selectedWorkoutID: selectionBinding
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let detail = library.detail(id: selectedWorkoutID) {
                WorkoutDetailView(detail: detail, summary: library.summary)
            } else {
                DashboardView(summary: library.summary, details: library.filteredDetails)
            }
        }
        .searchable(text: $library.searchText, placement: .sidebar)
        .toolbar {
            ToolbarItemGroup {
                Picker("Sport", selection: $library.selectedSport) {
                    Text("All").tag(Sport?.none)
                    ForEach(Sport.allCases) { sport in
                        Text(sport.displayName).tag(Sport?.some(sport))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button {
                    library.reloadDemoData()
                    selectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
                } label: {
                    Label("Reload Demo Library", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var selectionBinding: Binding<Int?> {
        Binding {
            selectedWorkoutID
        } set: { newValue in
            selectedWorkoutID = newValue ?? DemoWorkoutLibrary.defaultWorkoutID
        }
    }
}

