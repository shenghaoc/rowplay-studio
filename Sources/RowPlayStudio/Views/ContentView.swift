import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct ContentView: View {
    private static let dashboardSelectionID = -1

    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var syncController: Concept2SyncController
    @SceneStorage("selectedWorkoutID") private var storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
    @State private var detailNavigation = DetailNavigationState()

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(
                library: library,
                selectedWorkoutID: selectionBinding
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            NavigationStack(path: $detailNavigation.path) {
                detailContent
                    .navigationDestination(for: DetailNavigationState.Route.self) { route in
                        switch route {
                        case .replay(let workoutID):
                            if let detail = library.detail(id: workoutID) {
                                ReplayView(detail: detail)
                            } else {
                                ContentUnavailableView(
                                    "Workout Unavailable",
                                    systemImage: "exclamationmark.triangle",
                                    description: Text("Return to the workout library and select another workout.")
                                )
                            }
                        }
                    }
                    .onChange(of: selectedWorkoutID) {
                        detailNavigation.resetForSelectionChange()
                    }
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
                    reloadLibrary()
                } label: {
                    Label("Reload Workout Library", systemImage: "arrow.clockwise")
                }
                .disabled(syncController.syncState.inProgress)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if library.isEmpty && !preferences.demoModeEnabled {
            emptyState
        } else if let selectedWorkoutID, let detail = library.detail(id: selectedWorkoutID) {
            WorkoutDetailView(
                detail: detail,
                detailsRevision: library.detailsRevision,
                strokeSummary: library.strokeSummary(for: detail.id),
                summary: library.summary,
                comparisonCandidates: library.comparisonCandidates(for: detail.id),
                annotationStore: library.annotationStore,
                onUpdateDetail: library.updateDetail,
                onReplay: {
                    detailNavigation.showReplay(workoutID: detail.id)
                }
            )
        } else {
            DashboardView(
                library: library,
                summary: library.filteredSummary,
                personalBests: library.filteredPersonalBests,
                recentPaceWorkouts: library.filteredRecentPaceWorkouts
            )
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

    private func reloadLibrary() {
        Task {
            await syncController.loadCachedWorkouts(into: library)
            if library.librarySource == .demo {
                storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
            } else if let selectedWorkoutID, library.detail(id: selectedWorkoutID) == nil {
                storedSelectedWorkoutID = Self.dashboardSelectionID
            }
        }
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
