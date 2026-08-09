import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

/// Regression tests for the "Replay Workout" navigation fixes.
///
/// These tests verify the production detail-navigation state plus ReplayView
/// and ReplayState construction from demo workout data for every sport.
///
/// Two regression classes are covered:
/// 1. The detail column must sit in a `NavigationStack` (`ContentView.swift`)
///    so replay routes push at all.
/// 2. The replay command must resolve the *current* sidebar selection at
///    invocation time. macOS NSToolbar bridging can keep dispatching an
///    action closure captured during an earlier render pass, so a command
///    that bakes a workout ID into the closure replays the previously
///    selected workout (`showReplayForCurrentSelection` in
///    `DetailNavigationState.swift`).
///
/// **Boundary**: SwiftUI push behaviour cannot be verified in SwiftPM XCTest
/// without an external view-inspection library (e.g. ViewInspector), which
/// this project does not use. The `NavigationStack` wiring remains a
/// compile-time structural guarantee verified by `swift build`; route
/// creation, invocation-time selection resolution, and sidebar-reset
/// behavior are exercised directly through `DetailNavigationState`.
@MainActor
final class ReplayNavigationTests: XCTestCase {

    /// Demo lookup mirroring `WorkoutLibrary.detail(id:)` for command tests.
    private static let demoDetailsByID = Dictionary(
        uniqueKeysWithValues: DemoWorkoutLibrary.details.map { ($0.id, $0) }
    )

    /// Demo IDs used by the repro: 2000m test (rower), 1000m SkiErg,
    /// 8000m BikeErg, and the stroke-less 5000m steady row.
    private static let rowerWorkoutID = 1001
    private static let skiergWorkoutID = 1003
    private static let bikeWorkoutID = 1004
    private static let strokelessWorkoutID = 9001

    // MARK: - Production Navigation State

    func testReplayActionRoutesSelectedWorkout() {
        var navigation = DetailNavigationState()

        navigation.showReplay(workoutID: 42)

        XCTAssertEqual(navigation.path, [.replay(workoutID: 42)])
    }

    // MARK: - Invocation-Time Selection Resolution

    /// The core repro: a command closure created while workout A was
    /// selected must still replay workout B after the selection changes,
    /// because stale closures are exactly what AppKit menu and toolbar
    /// bridging dispatches.
    func testStaleReplayCommandClosureTargetsNewlySelectedWorkout() {
        var navigation = DetailNavigationState()
        var selectedWorkoutID: Int? = Self.rowerWorkoutID

        // Mirrors ContentView's wiring: the closure resolves the live
        // selection when invoked instead of capturing a workout ID. It is
        // created once here — while the 2000m rower test is selected — and
        // reused across selection changes, like a bridged menu or toolbar
        // action that outlives the render pass that produced it.
        let staleReplayCommand: () -> Void = {
            navigation.showReplay(
                for: selectedWorkoutID.flatMap { Self.demoDetailsByID[$0] },
                isLibraryLoading: false
            )
        }

        let selectionSequence: [(workoutID: Int, sport: Sport)] = [
            (Self.skiergWorkoutID, .skierg),
            (Self.bikeWorkoutID, .bike),
            (Self.rowerWorkoutID, .rower),
        ]
        for (workoutID, sport) in selectionSequence {
            selectedWorkoutID = workoutID
            // Mirrors ContentView's .onChange(of: selectedWorkoutID).
            navigation.resetForSelectionChange()

            staleReplayCommand()

            XCTAssertEqual(
                navigation.path,
                [.replay(workoutID: workoutID)],
                "Replay command must target the newly selected workout, not the one captured at closure creation"
            )
            XCTAssertEqual(
                Self.demoDetailsByID[workoutID]?.workout.sport,
                sport,
                "Selection sequence must exercise \(sport.displayName)"
            )
        }
    }

    func testReplayCommandReturnsPushedRouteForCurrentSelection() {
        var navigation = DetailNavigationState()

        let route = navigation.showReplay(
            for: Self.demoDetailsByID[Self.skiergWorkoutID],
            isLibraryLoading: false
        )

        XCTAssertEqual(route, .replay(workoutID: Self.skiergWorkoutID))
        XCTAssertEqual(navigation.path, [.replay(workoutID: Self.skiergWorkoutID)])
    }

    // MARK: - Availability Policy

    /// The menu item's enabled state and the push must never disagree: what
    /// the user sees enabled is exactly what invoking the command does.
    func testReplayUnavailabilityMatchesPushOutcome() {
        let cases: [(name: String, detail: WorkoutDetail?, loading: Bool, presented: Bool, expected: DetailNavigationState.ReplayUnavailability?)] = [
            ("available", Self.demoDetailsByID[Self.rowerWorkoutID], false, false, nil),
            ("loading", Self.demoDetailsByID[Self.rowerWorkoutID], true, false, .libraryLoading),
            ("already presented", Self.demoDetailsByID[Self.rowerWorkoutID], false, true, .alreadyPresented),
            ("no selection", nil, false, false, .noSelection),
            ("no stroke data", Self.demoDetailsByID[Self.strokelessWorkoutID], false, false, .noStrokeData),
        ]

        for testCase in cases {
            var navigation = DetailNavigationState()
            if testCase.presented {
                navigation.showReplay(workoutID: Self.bikeWorkoutID)
            }
            let routeCountBefore = navigation.path.count

            let unavailability = navigation.replayUnavailability(
                for: testCase.detail,
                isLibraryLoading: testCase.loading
            )
            let route = navigation.showReplay(
                for: testCase.detail,
                isLibraryLoading: testCase.loading
            )

            XCTAssertEqual(unavailability, testCase.expected, "\(testCase.name): unexpected availability")
            XCTAssertEqual(
                route == nil,
                unavailability != nil,
                "\(testCase.name): disabled state must match whether the push happens"
            )
            XCTAssertEqual(
                navigation.path.count,
                unavailability == nil ? routeCountBefore + 1 : routeCountBefore,
                "\(testCase.name): unavailable command must not mutate the path"
            )
        }
    }

    func testStrokelessDemoWorkoutExistsForAvailabilityCoverage() {
        XCTAssertEqual(
            Self.demoDetailsByID[Self.strokelessWorkoutID]?.workout.hasStrokeData,
            false,
            "Demo data must include a stroke-less workout for the no-stroke-data guard"
        )
    }

    func testReplayCommandIsEnabledOnlyWhenAvailable() {
        XCTAssertTrue(ReplayCommand(unavailability: nil, run: {}).isEnabled)
        for unavailability: DetailNavigationState.ReplayUnavailability in [
            .libraryLoading, .noSelection, .noStrokeData, .alreadyPresented,
        ] {
            XCTAssertFalse(
                ReplayCommand(unavailability: unavailability, run: {}).isEnabled,
                "\(unavailability) must disable the Replay menu item"
            )
        }
    }

    func testSidebarSelectionClearsPresentedReplay() {
        var navigation = DetailNavigationState()
        navigation.showReplay(workoutID: 42)

        navigation.resetForSelectionChange()

        XCTAssertTrue(navigation.path.isEmpty)
    }

    // MARK: - Demo Data Coverage

    func testDemoDataCoversAllSports() {
        for sport in [Sport.rower, .skierg, .bike] {
            XCTAssertNotNil(
                DemoWorkoutLibrary.details.first { $0.workout.sport == sport },
                "Demo data must include a \(sport.displayName) workout"
            )
        }
    }

    // MARK: - ReplayView Construction (crash guard per sport)

    func testReplayViewConstructsForEverySport() {
        for sport in [Sport.rower, .skierg, .bike] {
            let detail = DemoWorkoutLibrary.details.first { $0.workout.sport == sport }
            XCTAssertNotNil(detail, "Missing demo detail for \(sport.displayName)")
            guard let detail else { continue }
            // ReplayView is a struct — init cannot return nil. A crash here
            // would abort the test process, which is the real guard.
            _ = ReplayView(detail: detail)
        }
    }

    // MARK: - ReplayState Init from Demo Strokes

    func testReplayStateInitialisesFromDemoWorkout() {
        let detail = DemoWorkoutLibrary.details.first
        XCTAssertNotNil(detail, "Demo data must include at least one workout")
        guard let detail else { return }
        let state = ReplayState(strokes: detail.strokes)
        XCTAssertGreaterThan(state.duration, 0, "ReplayState duration must be > 0 for replay to be meaningful")
        XCTAssertFalse(state.playing, "ReplayState must start paused")
    }
}
