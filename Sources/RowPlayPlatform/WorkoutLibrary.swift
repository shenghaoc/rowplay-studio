import Combine
import Foundation
import RowPlayCore

@MainActor
public final class WorkoutLibrary: ObservableObject {
    @Published public var details: [WorkoutDetail] {
        didSet {
            detailsRevision &+= 1
            guard !suppressDerivedUpdates else { return }
            updateAllDerivedData()
        }
    }
    @Published public var query: WorkoutListQuery {
        didSet {
            guard !suppressDerivedUpdates else { return }
            let sportChanged = query.sport != oldValue.sport
            updateQueryDerivedData(sportChanged: sportChanged)
        }
    }
    @Published public private(set) var pbIds: Set<Int> = []
    @Published public var liveState: LiveModeState = LiveModeState()
    @Published public private(set) var liveSample: LiveWorkoutSample?
    /// Which data source the library last loaded from.
    public private(set) var librarySource: WorkoutLibrarySource = .empty
    public let annotationStore: any AnnotationStore

    private(set) var liveSource: any LiveSource = MockLiveSource()
    private let demoLiveSampleGenerator = DemoLiveSampleGenerator()

    // Caches to prevent expensive O(N) and O(N log N) recomputations on every render
    public private(set) var workouts: [Workout] = []
    public private(set) var filteredWorkouts: [Workout] = []
    public private(set) var filteredDetails: [WorkoutDetail] = []
    public private(set) var summary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])
    public private(set) var filteredSummary: DashboardSummary = WorkoutAnalytics.dashboardSummary(for: [])
    public private(set) var filteredPersonalBests: [DashboardPersonalBest] = []
    public private(set) var filteredRecentPaceWorkouts: [Workout] = []

    /// Cached comparison candidates for the active workout, invalidated when `details` changes.
    private var cachedComparisonCandidates: (workoutID: Int, candidates: [WorkoutDetail])?

    /// Cached ghost candidates for replay rival selection, invalidated when `details` changes.
    private var cachedGhostCandidates: (workoutID: Int, candidates: [WorkoutDetail])?

    /// Lightweight change token for views that must react to detail-content updates
    /// without comparing complete stroke and split histories during body evaluation.
    public private(set) var detailsRevision: UInt64 = 0

    /// When true, `didSet` observers skip derived-data recomputation.
    /// Used by `loadFromSource` to batch `details` and `query` updates into one pass.
    private var suppressDerivedUpdates = false

    /// Cached lookup from workout ID → WorkoutDetail, rebuilt when `details` changes.
    private var detailByID: [Int: WorkoutDetail] = [:]
    /// Cached stroke summaries for detail accessibility labels and metrics.
    private var strokeSummaryByWorkoutID: [Int: StrokeSummary] = [:]
    private let defaults: UserDefaults
    private var demoModeEnabled: Bool
    public private(set) var demoDetailIDs: Set<Int>
    private static let demoDetailsByID = Dictionary(
        uniqueKeysWithValues: DemoWorkoutLibrary.details.map { ($0.id, $0) }
    )

    public init(
        details: [WorkoutDetail],
        query: WorkoutListQuery = WorkoutQuery.defaultQuery,
        annotationStore: any AnnotationStore = InMemoryAnnotationStore(),
        defaults: UserDefaults = .standard
    ) {
        self.details = details
        self.query = query
        self.annotationStore = annotationStore
        self.defaults = defaults
        demoModeEnabled = Self.persistedDemoModeEnabled(in: defaults)
        demoDetailIDs = Self.demoIDs(in: details)
        if !details.isEmpty {
            librarySource = demoDetailIDs.count == details.count ? .demo : .cache
        }
        updateAllDerivedData()
        observeDemoModeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Creates a library populated with demo data if the persisted preference allows it.
    public static func demo(defaults: UserDefaults = .standard) -> WorkoutLibrary {
        let demoEnabled = persistedDemoModeEnabled(in: defaults)
        return WorkoutLibrary(details: demoEnabled ? DemoWorkoutLibrary.details : [], defaults: defaults)
    }

    /// Creates a deterministic demo library for scripted automation.
    ///
    /// Unlike ``demo(defaults:)``, this intentionally ignores the persisted
    /// Demo Mode preference so automation always starts with the same fixtures.
    public static func automationDemo(defaults: UserDefaults = .standard) -> WorkoutLibrary {
        WorkoutLibrary(details: DemoWorkoutLibrary.details, defaults: defaults)
    }

    public private(set) var availableWorkoutTypes: [String] = []

    public func detail(id: Int) -> WorkoutDetail? {
        detailByID[id]
    }

    public func strokeSummary(for workoutID: Int) -> StrokeSummary {
        strokeSummaryByWorkoutID[workoutID] ?? .empty
    }

    public func updateDetail(_ detail: WorkoutDetail) {
        guard let index = details.firstIndex(where: { $0.id == detail.id }) else { return }
        var updatedDetails = details
        updatedDetails[index] = detail
        details = updatedDetails
    }

    public func comparisonCandidates(for workoutID: Int) -> [WorkoutDetail] {
        if let cachedComparisonCandidates,
           cachedComparisonCandidates.workoutID == workoutID {
            return cachedComparisonCandidates.candidates
        }
        guard let target = detailByID[workoutID] else { return [] }
        let targetContext = comparableContext(for: target.workout)

        let candidates = details
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

        cachedComparisonCandidates = (workoutID, candidates)
        return candidates
    }

    /// Ranked comparable past-session candidates for ghost replay.
    /// Uses ``GhostPick/rankedGhostCandidates(_:current:)`` and resolves
    /// ranked ``Workout`` values back to ``WorkoutDetail`` through the detail
    /// cache. Candidates with empty stroke arrays are excluded even if
    /// `hasStrokeData` is true.
    public func ghostCandidates(for workoutID: Int) -> [WorkoutDetail] {
        if let cachedGhostCandidates,
           cachedGhostCandidates.workoutID == workoutID {
            return cachedGhostCandidates.candidates
        }
        guard let target = detailByID[workoutID] else { return [] }
        let context = GhostPickContext(
            id: target.id,
            distance: target.workout.distance,
            sport: target.workout.sport,
            time: target.workout.time,
            workoutType: target.workout.workoutType
        )
        let ranked = GhostPick.rankedGhostCandidates(
            candidates: workouts,
            current: context
        )
        let candidates = ranked.compactMap { w -> WorkoutDetail? in
            guard let detail = detailByID[w.id], !detail.strokes.isEmpty else { return nil }
            return detail
        }
        cachedGhostCandidates = (workoutID, candidates)
        return candidates
    }

    /// The default ghost candidate (best match) for a workout, or nil when
    /// no comparable past session exists.
    public func defaultGhostCandidate(for workoutID: Int) -> WorkoutDetail? {
        ghostCandidates(for: workoutID).first
    }

    public func reloadDemoData() {
        details = DemoWorkoutLibrary.details
        demoDetailIDs = Set(DemoWorkoutLibrary.details.map(\.id))
        librarySource = .demo
        query = WorkoutQuery.defaultQuery
    }

    public var isEmpty: Bool {
        details.isEmpty
    }

    public func clearData() {
        details = []
        demoDetailIDs = []
        librarySource = .empty
        query = WorkoutQuery.defaultQuery
    }

    /// Disable demo mode if currently enabled (e.g. after syncing real Concept2 data).
    public func disableDemoModeIfNeeded() {
        if demoModeEnabled {
            demoModeEnabled = false
            defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        }
    }

    /// Reload the library from the cache, falling back to demo data or empty as appropriate.
    ///
    /// Uses the library's internal ``demoModeEnabled`` state (persisted in UserDefaults)
    /// to decide the fallback. This replaces all existing details with the fresh load result.
    /// Cache errors propagate to the caller and do not silently fall back to demo data.
    public func loadFromSource(cache: WorkoutCache) async throws {
        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: demoModeEnabled
        )
        applySnapshot(snapshot)
    }

    /// Reload from cache without demo fallback, then disable demo mode after the
    /// cache result has been applied successfully.
    public func loadSyncedSource(cache: WorkoutCache) async throws {
        let snapshot = try await WorkoutLibraryLoader.load(
            cache: cache,
            demoModeEnabled: false
        )
        applySnapshot(snapshot)
        disableDemoModeIfNeeded()
    }

    private func applySnapshot(_ snapshot: WorkoutLibrarySnapshot) {
        let sourceChanged = snapshot.source != librarySource
        suppressDerivedUpdates = true
        details = snapshot.details
        librarySource = snapshot.source
        if snapshot.source == .demo {
            demoDetailIDs = Self.demoIDs(in: snapshot.details)
        } else {
            demoDetailIDs = []
        }
        if sourceChanged {
            query = WorkoutQuery.defaultQuery
        }
        suppressDerivedUpdates = false
        updateAllDerivedData()
    }

    // MARK: - Demo Mode Observation

    private func observeDemoModeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDemoModeChanged),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
    }

    @objc private nonisolated func handleDemoModeChanged() {
        Task { @MainActor [weak self] in
            self?.updateDemoModeState()
        }
    }

    private func updateDemoModeState() {
        let demoEnabled = Self.persistedDemoModeEnabled(in: defaults)
        guard demoEnabled != demoModeEnabled else { return }
        demoModeEnabled = demoEnabled

        if demoEnabled {
            guard details.isEmpty else { return }
            details = DemoWorkoutLibrary.details
            demoDetailIDs = Self.demoIDs(in: details)
            librarySource = .demo
            query = WorkoutQuery.defaultQuery
        } else if !details.isEmpty {
            let previousCount = details.count
            let previousSource = librarySource
            if !demoDetailIDs.isEmpty {
                details.removeAll(where: { demoDetailIDs.contains($0.id) })
                demoDetailIDs = []
            }
            if librarySource == .demo {
                librarySource = .empty
            }
            if details.count != previousCount || librarySource != previousSource {
                query = WorkoutQuery.defaultQuery
            }
        }
    }

    private static func persistedDemoModeEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppPreferences.demoModeEnabledKey) as? Bool ?? true
    }

    private static func demoIDs(in details: [WorkoutDetail]) -> Set<Int> {
        Set(details.compactMap { detail in
            demoDetailsByID[detail.id] == detail ? detail.id : nil
        })
    }

    // MARK: - Live Mode

    public func startLiveMode(at date: Date = Date()) {
        liveState.start()
        advanceDemoLiveSample(at: date)
    }

    public func stopLiveMode() {
        liveState.stop()
        liveSample = nil
        demoLiveSampleGenerator.reset()
    }

    public func setLiveInterval(_ sec: Int) {
        let previousInterval = liveState.intervalSec
        liveState.intervalChanged(sec)
        guard liveState.enabled, liveState.intervalSec != previousInterval else { return }
        liveState.tickScheduled(at: Date().addingTimeInterval(TimeInterval(liveState.intervalSec)))
    }

    public func setLiveSource(_ source: any LiveSource) {
        liveSource = source
    }

    public func advanceDemoLiveSample(at date: Date = Date()) {
        guard liveState.enabled else { return }
        liveState.pollStarted()
        liveSample = demoLiveSampleGenerator.nextSample(at: date)
        liveState.pollSucceeded(at: date)
        liveState.tickScheduled(at: date.addingTimeInterval(TimeInterval(liveState.intervalSec)))
    }

    public func advanceDemoLiveSampleIfDue(at date: Date = Date()) {
        guard liveState.enabled else { return }
        guard let nextPollAt = liveState.nextPollAt else {
            advanceDemoLiveSample(at: date)
            return
        }
        if nextPollAt <= date {
            advanceDemoLiveSample(at: date)
        }
    }

    public func ingestLiveResult(_ result: LivePollResult) {
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
        strokeSummaryByWorkoutID = Dictionary(
            details.map { ($0.id, WorkoutAnalytics.strokeSummary(for: $0.strokes)) },
            uniquingKeysWith: { first, _ in first }
        )
        workouts = details.map(\.workout)
        summary = WorkoutAnalytics.dashboardSummary(for: workouts)
        availableWorkoutTypes = Array(Set(workouts.map(\.workoutType))).sorted()
        cachedComparisonCandidates = nil
        cachedGhostCandidates = nil
        updateQueryDerivedData(sportChanged: true)
    }

    private func updateQueryDerivedData(sportChanged: Bool) {
        if sportChanged {
            pbIds = WorkoutQuery.pbWorkoutIds(workouts: workouts, sport: query.sport)
        }
        filteredWorkouts = WorkoutQuery.filterAndSortWorkouts(workouts, query: query, pbIds: pbIds)
        filteredDetails = filteredWorkouts.compactMap { detailByID[$0.id] }
        filteredSummary = WorkoutAnalytics.dashboardSummary(for: filteredWorkouts)
        filteredPersonalBests = WorkoutAnalytics.dashboardPersonalBests(for: filteredWorkouts, pbIds: pbIds)

        // Use the active sport filter if set; otherwise default to the sport with the most workouts.
        let sport: Sport = query.sport ?? {
            let grouped = Dictionary(grouping: filteredWorkouts, by: \.sport)
            return grouped.max(by: { $0.value.count < $1.value.count })?.key ?? .rower
        }()
        filteredRecentPaceWorkouts = WorkoutAnalytics.recentPaceWorkouts(for: filteredWorkouts, sport: sport, limit: 10)
    }
}
