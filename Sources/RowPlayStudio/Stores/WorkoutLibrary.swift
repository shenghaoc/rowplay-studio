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
    private(set) var summary: DashboardSummary = DashboardSummary(sessions: 0, totalDistance: 0, challengeDistance: 0, totalTime: 0, averagePace: 0, bySport: [])
    private(set) var filteredSummary: DashboardSummary = DashboardSummary(sessions: 0, totalDistance: 0, challengeDistance: 0, totalTime: 0, averagePace: 0, bySport: [])

    /// Cached lookup from workout ID → WorkoutDetail, rebuilt when `details` changes.
    private var detailByID: [Int: WorkoutDetail] = [:]

    init(details: [WorkoutDetail], query: WorkoutListQuery = WorkoutQuery.defaultQuery) {
        self.details = details
        self.query = query

        let initialWorkouts = details.map(\.workout)
        self.workouts = initialWorkouts
        self.summary = WorkoutAnalytics.dashboardSummary(for: initialWorkouts)
        self.detailByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.pbIds = WorkoutQuery.pbWorkoutIds(workouts: initialWorkouts, sport: query.sport)
        self.filteredWorkouts = WorkoutQuery.filterAndSortWorkouts(initialWorkouts, query: query, pbIds: self.pbIds)
        self.filteredDetails = self.filteredWorkouts.compactMap { self.detailByID[$0.id] }
        self.filteredSummary = WorkoutAnalytics.dashboardSummary(for: self.filteredWorkouts)
    }

    static func demo() -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details)
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

    private func updateAllDerivedData() {
        detailByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workouts = details.map(\.workout)
        summary = WorkoutAnalytics.dashboardSummary(for: workouts)
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
