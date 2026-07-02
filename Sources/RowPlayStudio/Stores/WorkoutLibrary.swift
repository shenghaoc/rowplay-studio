import Combine
import Foundation
import RowPlayCore

@MainActor
final class WorkoutLibrary: ObservableObject {
    @Published var details: [WorkoutDetail] {
        didSet {
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

    init(details: [WorkoutDetail], query: WorkoutListQuery = WorkoutQuery.defaultQuery) {
        self.details = details
        self.query = query
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
        let detailByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return filteredWorkouts.compactMap { detailByID[$0.id] }
    }

    var summary: DashboardSummary {
        WorkoutAnalytics.dashboardSummary(for: workouts)
    }

    var availableWorkoutTypes: [String] {
        Array(Set(workouts.map(\.workoutType))).sorted()
    }

    func detail(id: Int) -> WorkoutDetail? {
        details.first { $0.id == id }
    }

    func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        query = WorkoutQuery.defaultQuery
    }

    private func refreshPBIds() {
        pbIds = WorkoutQuery.pbWorkoutIds(workouts: workouts, sport: query.sport)
    }
}
