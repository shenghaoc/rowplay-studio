import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

/// Regression tests for the "Replay Workout" navigation fix.
///
/// These tests verify that ReplayView and ReplayState can be constructed from
/// demo workout data for every sport — the precondition for the navigation
/// push to succeed.
///
/// **Boundary**: The actual fix is wrapping `NavigationSplitView`'s detail
/// column in `NavigationStack` (`ContentView.swift`). SwiftUI push behaviour
/// cannot be verified in SwiftPM XCTest without an external view-inspection
/// library (e.g. ViewInspector), which this project does not use. The
/// `NavigationStack` presence is a compile-time structural guarantee verified
/// by `swift build` and manual testing.
@MainActor
final class ReplayNavigationTests: XCTestCase {

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
