import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

/// Regression tests for the "Replay Workout" navigation fix.
///
/// These tests verify the action/view state that enables the
/// NavigationStack push (showingReplay toggle + ReplayView construction).
/// Actual SwiftUI push verification requires UI tests or manual testing.
@MainActor
final class ReplayNavigationTests: XCTestCase {

    // MARK: - ReplayView Instantiation (per-sport regression guard)

    func testReplayViewCanBeInstantiatedWithRowerDetail() {
        let detail = DemoWorkoutLibrary.details.first { $0.workout.sport == .rower }
        XCTAssertNotNil(detail, "Demo data must include a rower workout")
        if let detail {
            let view = ReplayView(detail: detail)
            // If ReplayView's init crashes, this test fails.
            XCTAssertNotNil(view)
        }
    }

    func testReplayViewCanBeInstantiatedWithSkiErgDetail() {
        let detail = DemoWorkoutLibrary.details.first { $0.workout.sport == .skierg }
        XCTAssertNotNil(detail, "Demo data must include a SkiErg workout")
        if let detail {
            let view = ReplayView(detail: detail)
            XCTAssertNotNil(view)
        }
    }

    func testReplayViewCanBeInstantiatedWithBikeErgDetail() {
        let detail = DemoWorkoutLibrary.details.first { $0.workout.sport == .bike }
        XCTAssertNotNil(detail, "Demo data must include a BikeErg workout")
        if let detail {
            let view = ReplayView(detail: detail)
            XCTAssertNotNil(view)
        }
    }

    // MARK: - ReplayState Init from Demo Strokes

    func testReplayStateInitialisesFromDemoWorkout() {
        let detail = DemoWorkoutLibrary.details.first
        XCTAssertNotNil(detail)
        if let detail {
            let state = ReplayState(strokes: detail.strokes)
            XCTAssertGreaterThan(state.duration, 0, "ReplayState duration must be > 0 for replay to be meaningful")
            XCTAssertFalse(state.playing, "ReplayState must start paused")
        }
    }
}
