import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct ContentView: View {
    private static let dashboardSelectionID = -1
    private static let skeletonWorkouts = DemoWorkoutLibrary.details.map(\.workout)
    private static let skeletonSummary = WorkoutAnalytics.dashboardSummary(for: skeletonWorkouts)
    private static let skeletonPersonalBests = WorkoutAnalytics.dashboardPersonalBests(
        for: skeletonWorkouts,
        pbIds: PersonalBests.pbWorkoutIds(for: skeletonWorkouts)
    )
    private static let skeletonRecentPaceWorkouts = Array(skeletonWorkouts.prefix(10))

    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var syncController: Concept2SyncController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("selectedWorkoutID") private var storedSelectedWorkoutID = DemoWorkoutLibrary.defaultWorkoutID
    @State private var detailNavigation = DetailNavigationState()
    @State private var showSettings = false

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(
                library: library,
                selectedWorkoutID: selectionBinding
            )
            .redacted(reason: syncController.isLoading ? .placeholder : [])
            .disabled(syncController.isLoading)
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            NavigationStack(path: $detailNavigation.path) {
                Group {
                    if syncController.isLoading {
                        DashboardView(
                            library: library,
                            summary: Self.skeletonSummary,
                            personalBests: Self.skeletonPersonalBests,
                            recentPaceWorkouts: Self.skeletonRecentPaceWorkouts
                        )
                        .redacted(reason: .placeholder)
                        .disabled(true)
                    } else {
                        detailContent
                    }
                }
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
        #if os(macOS)
        .background {
            Button("Dashboard") {
                storedSelectedWorkoutID = Self.dashboardSelectionID
            }
            .keyboardShortcut("1", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        #endif
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
                .disabled(syncController.isLoading)
                .help(syncController.isLoading
                      ? "Cannot reload while syncing"
                      : "Fetch the latest workouts from your Concept2 Logbook")
                .keyboardShortcut("r", modifiers: .command)
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
        VStack(spacing: AppDesign.Spacing.xxxLarge) {
            VStack(spacing: AppDesign.Spacing.large) {
                Image(systemName: "figure.rower")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(AppDesign.MetricColor.duration)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

                VStack(spacing: AppDesign.Spacing.small) {
                    Text("Ready When You Are")
                        .font(.title.weight(.semibold))

                    Text("Enable Demo Mode to explore sample workouts with preloaded data, or connect your Concept2 logbook to sync your training history.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            VStack(spacing: AppDesign.Spacing.medium) {
                Button("Enable Demo Mode") {
                    preferences.demoModeEnabled = true
                }
                .buttonStyle(.borderedProminent)

                #if os(macOS)
                SettingsLink {
                    Text("Open Settings")
                }
                #else
                Button("Open Settings") {
                    showSettings = true
                }
                .buttonStyle(.borderedProminent)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppDesign.Spacing.xxxLarge)
        #if !os(macOS)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif
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
