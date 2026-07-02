import Combine
import Foundation
import RowPlayCore

@MainActor
final class WorkoutLibrary: ObservableObject {
    @Published var details: [WorkoutDetail] {
        didSet {
            rebuildDetailIndex()
            refreshPBIds()
        }
    }
    @Published var query: WorkoutListQuery {
        didSet {
            // PBs depend only on workouts and sport filter, not sort/dir/search/etc.
            if query.sport != oldValue.sport {
                refreshPBIds()
            }
        }
    }
    @Published private(set) var pbIds: Set<Int> = []

    /// Cached lookup from workout ID → WorkoutDetail, rebuilt when `details` changes.
    private var detailByID: [Int: WorkoutDetail] = [:]

    init(details: [WorkoutDetail], query: WorkoutListQuery = WorkoutQuery.defaultQuery) {
        self.details = details
        self.query = query
        rebuildDetailIndex()
        refreshPBIds()
    }

    static func demo() -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details)
    }

    var workouts: [Workout] {
        details.map(\.workout)
    }

    var filteredWorkouts: [Workout] {
        WorkoutQuery.filterAndSortWorkouts(workouts, query: query, pbIds: pbIds)
    }

    var filteredDetails: [WorkoutDetail] {
        filteredWorkouts.compactMap { detailByID[$0.id] }
    }

    var summary: DashboardSummary {
        WorkoutAnalytics.dashboardSummary(for: workouts)
    }

    /// Summary scoped to the active query filters (sport, date range, etc.).
    var filteredSummary: DashboardSummary {
        WorkoutAnalytics.dashboardSummary(for: filteredWorkouts)
    }

    var availableWorkoutTypes: [String] {
        Array(Set(workouts.map(\.workoutType))).sorted()
    }

    func detail(id: Int) -> WorkoutDetail? {
        detailByID[id]
    }

    func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        query = WorkoutQuery.defaultQuery
    }

    private func rebuildDetailIndex() {
        detailByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func refreshPBIds() {
        pbIds = WorkoutQuery.pbWorkoutIds(workouts: workouts, sport: query.sport)
    }
}
