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
    @Published var liveState: LiveModeState = LiveModeState()
    @Published private(set) var liveSample: LiveWorkoutSample?
    let annotationStore: any AnnotationStore

    private(set) var liveSource: any LiveSource = MockLiveSource()
    private let demoLiveSampleGenerator = DemoLiveSampleGenerator()

    // Caches to prevent expensive O(N) and O(N log N) recomputations on every render
    private(set) var workouts: [Workout] = []
    private(set) var filteredWorkouts: [Workout] = []
    private(set) var filteredDetails: [WorkoutDetail] = []
    private(set) var summary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])
    private(set) var filteredSummary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])

    /// Cached lookup from workout ID → WorkoutDetail, rebuilt when `details` changes.
    private var detailByID: [Int: WorkoutDetail] = [:]

    init(
        details: [WorkoutDetail],
        query: WorkoutListQuery = WorkoutQuery.defaultQuery,
        annotationStore: any AnnotationStore = InMemoryAnnotationStore()
    ) {
        self.details = details
        self.query = query
        self.annotationStore = annotationStore
        updateAllDerivedData()
        observeDemoModeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Creates a library populated with demo data if the persisted preference allows it.
    static func demo() -> WorkoutLibrary {
        let demoEnabled = UserDefaults.standard.object(forKey: "demoModeEnabled") as? Bool ?? true
        return WorkoutLibrary(details: demoEnabled ? DemoWorkoutLibrary.details : [])
    }

    private(set) var availableWorkoutTypes: [String] = []

    func detail(id: Int) -> WorkoutDetail? {
        detailByID[id]
    }

    func updateDetail(_ detail: WorkoutDetail) {
        guard let index = details.firstIndex(where: { $0.id == detail.id }) else { return }
        var updatedDetails = details
        updatedDetails[index] = detail
        details = updatedDetails
    }

    func comparisonCandidates(for workoutID: Int) -> [WorkoutDetail] {
        guard let target = detailByID[workoutID] else { return [] }
        let targetContext = comparableContext(for: target.workout)

        return details
            .filter { candidate in
                candidate.id != workoutID && candidate.workout.sport == target.workout.sport
            }
            .sorted { lhs, rhs in
                let lhsComparable = ComparabilityGuard.areComparable(
                    targetContext,
                    comparableContext(for: lhs.workout)
                )
                let rhsComparable = ComparabilityGuard.areComparable(
                    targetContext,
                    comparableContext(for: rhs.workout)
                )
                if lhsComparable != rhsComparable {
                    return lhsComparable && !rhsComparable
                }

                let lhsDistanceDelta = abs(lhs.workout.distance - target.workout.distance)
                let rhsDistanceDelta = abs(rhs.workout.distance - target.workout.distance)
                if lhsDistanceDelta != rhsDistanceDelta {
                    return lhsDistanceDelta < rhsDistanceDelta
                }

                let lhsTimeDelta = abs(lhs.workout.time - target.workout.time)
                let rhsTimeDelta = abs(rhs.workout.time - target.workout.time)
                if lhsTimeDelta != rhsTimeDelta {
                    return lhsTimeDelta < rhsTimeDelta
                }

                return lhs.workout.date > rhs.workout.date
            }
    }

    func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        query = WorkoutQuery.defaultQuery
    }

    var isEmpty: Bool {
        details.isEmpty
    }

    func clearData() {
        details = []
        query = WorkoutQuery.defaultQuery
    }

    // MARK: - Demo Mode Observation

    private func observeDemoModeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDemoModeChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleDemoModeChanged() {
        let demoEnabled = UserDefaults.standard.object(forKey: "demoModeEnabled") as? Bool ?? true
        if demoEnabled && details.isEmpty {
            details = DemoWorkoutLibrary.details
            query = WorkoutQuery.defaultQuery
        } else if !demoEnabled && !details.isEmpty {
            details = []
            query = WorkoutQuery.defaultQuery
        }
    }

    // MARK: - Live Mode

    func startLiveMode(at date: Date = Date()) {
        liveState.start()
        advanceDemoLiveSample(at: date)
    }

    func stopLiveMode() {
        liveState.stop()
        liveSample = nil
        demoLiveSampleGenerator.reset()
    }

    func setLiveInterval(_ sec: Int) {
        let previousInterval = liveState.intervalSec
        liveState.intervalChanged(sec)
        guard liveState.enabled, liveState.intervalSec != previousInterval else { return }
        liveState.tickScheduled(at: Date().addingTimeInterval(TimeInterval(liveState.intervalSec)))
    }

    func setLiveSource(_ source: any LiveSource) {
        liveSource = source
    }

    func advanceDemoLiveSample(at date: Date = Date()) {
        guard liveState.enabled else { return }
        liveState.pollStarted()
        liveSample = demoLiveSampleGenerator.nextSample(at: date)
        liveState.pollSucceeded(at: date)
        liveState.tickScheduled(at: date.addingTimeInterval(TimeInterval(liveState.intervalSec)))
    }

    func advanceDemoLiveSampleIfDue(at date: Date = Date()) {
        guard liveState.enabled else { return }
        guard let nextPollAt = liveState.nextPollAt else {
            advanceDemoLiveSample(at: date)
            return
        }
        if nextPollAt <= date {
            advanceDemoLiveSample(at: date)
        }
    }

    func ingestLiveResult(_ result: LivePollResult) {
        var existingIDs = Set(details.map(\.id))
        var newWorkouts: [Workout] = []
        for workout in result.workouts where !existingIDs.contains(workout.id) {
            newWorkouts.append(workout)
            existingIDs.insert(workout.id)
        }
        guard !newWorkouts.isEmpty else { return }
        let newDetails = newWorkouts.map { WorkoutDetail(workout: $0, strokes: [], splits: []) }
        details.append(contentsOf: newDetails)
    }

    private func comparableContext(for workout: Workout) -> ComparableContext {
        ComparableContext(
            sport: workout.sport,
            distance: workout.distance,
            time: workout.time,
            workoutType: workout.workoutType
        )
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
