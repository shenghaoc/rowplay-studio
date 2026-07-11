# Bugfix: Replay Workout Navigation

## Regression

After the Phase 8B articulated-rigs merge, clicking "Replay Workout" from a
workout detail view does not push the replay screen. The button is visible and
tappable, but `showingReplay = true` never triggers a navigation push because
`WorkoutDetailView` is rendered inside a `NavigationSplitView` detail column
that lacks a `NavigationStack` ancestor. On macOS 26 the implicit
`NavigationStack` that `NavigationSplitView` formerly provided for the detail
column is no longer guaranteed.

## Scope

- **In scope**: Wrap the `NavigationSplitView` detail column content in
  `NavigationStack` so `.navigationDestination(isPresented:)` works correctly.
- **Out of scope**: Phase 8B rig logic, `ReplayState` internals, sidebar
  changes, or any work beyond the minimal navigation fix.

## Acceptance Criteria

1. In demo mode, clicking "Replay Workout" on any workout detail view pushes
   `ReplayView` onto the navigation stack.
2. Pressing the back button returns to the workout detail view.
3. RowErg, SkiErg, and BikeErg workouts all navigate to replay correctly.
4. All existing tests continue to pass (`swift test`).
5. `swift build` succeeds with zero warnings related to navigation.
6. A regression test exercises the navigation-action state that enables
   presentation.

## Non-Goals

- Re-architecting the app's navigation model.
- Changes to `ReplayState`, `ReplayPlaybackClock`, or sport rig logic.
- Adding or modifying any 3D scene code.
