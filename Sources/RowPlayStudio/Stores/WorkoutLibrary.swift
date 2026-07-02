import Combine
import Foundation
import RowPlayCore

@MainActor
final class WorkoutLibrary: ObservableObject {
    @Published var details: [WorkoutDetail]
    @Published var query: WorkoutListQuery

    init(details: [WorkoutDetail], query: WorkoutListQuery = WorkoutQuery.defaultQuery) {
        self.details = details
        self.query = query
    }

    static func demo() -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details)
    }

    var workouts: [Workout] {
        details.map(\.workout)
    }

    var filteredDetails: [WorkoutDetail] {
        let filteredWorkouts = WorkoutQuery.filterAndSortWorkouts(workouts, query: query, pbIds: pbIds)
        let detailByID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        return filteredWorkouts.compactMap { detailByID[$0.id] }
    }

    var summary: DashboardSummary {
        WorkoutAnalytics.dashboardSummary(for: workouts)
    }

    var pbIds: Set<Int> {
        WorkoutQuery.pbWorkoutIds(workouts: workouts)
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
}

