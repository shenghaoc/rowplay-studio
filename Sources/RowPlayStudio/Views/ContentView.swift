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
                DashboardView(
                    summary: library.summary,
                    details: library.filteredDetails,
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

