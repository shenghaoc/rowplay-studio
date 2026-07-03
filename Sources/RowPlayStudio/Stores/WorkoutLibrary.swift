import Combine
import Foundation
import RowPlayCore

@MainActor
final class WorkoutLibrary: ObservableObject {
    @Published var details: [WorkoutDetail] {
        didSet {
            updateAllDerivedData()
        }
    }
    @Published var query: WorkoutListQuery {
        didSet {
            let sportChanged = query.sport != oldValue.sport
            updateQueryDerivedData(sportChanged: sportChanged)
        }
    }
    @Published private(set) var pbIds: Set<Int> = []

    // Caches to prevent expensive O(N) and O(N log N) recomputations on every render
    private(set) var workouts: [Workout] = []
    private(set) var filteredWorkouts: [Workout] = []
    private(set) var filteredDetails: [WorkoutDetail] = []
    private(set) var summary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])
    private(set) var filteredSummary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])

    /// Cached lookup from workout ID → WorkoutDetail, rebuilt when `details` changes.
    private var detailByID: [Int: WorkoutDetail] = [:]

    init(details: [WorkoutDetail], query: WorkoutListQuery = WorkoutQuery.defaultQuery) {
        self.details = details
        self.query = query
        updateAllDerivedData()
    }

    static func demo() -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details)
    }

    private(set) var availableWorkoutTypes: [String] = []

    func detail(id: Int) -> WorkoutDetail? {
        detailByID[id]
    }

    func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        query = WorkoutQuery.defaultQuery
    }

    private func updateAllDerivedData() {
        detailByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workouts = details.map(\.workout)
        summary = WorkoutAnalytics.dashboardSummary(for: workouts)
        availableWorkoutTypes = Array(Set(workouts.map(\.workoutType))).sorted()
        updateQueryDerivedData(sportChanged: true)
    }

    private func updateQueryDerivedData(sportChanged: Bool) {
        if sportChanged {
            pbIds = WorkoutQuery.pbWorkoutIds(workouts: workouts, sport: query.sport)
        }
        filteredWorkouts = WorkoutQuery.filterAndSortWorkouts(workouts, query: query, pbIds: pbIds)
        filteredDetails = filteredWorkouts.compactMap { detailByID[$0.id] }
        filteredSummary = WorkoutAnalytics.dashboardSummary(for: filteredWorkouts)
    }
}
