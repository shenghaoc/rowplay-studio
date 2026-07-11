# Design: Replay Workout Navigation Fix

## Root Cause

`ContentView.swift` uses a `NavigationSplitView` as the app's root navigation
container. The `detail:` closure directly renders content views
(`DashboardView`, `WorkoutDetailView`, etc.) without wrapping them in a
`NavigationStack`. On macOS 26, `NavigationSplitView` no longer implicitly
provides a `NavigationStack` for the detail column, so
`.navigationDestination(isPresented:)` — used inside `WorkoutDetailView` to
push `ReplayView` — has no navigation stack to push onto and is silently
ignored.

This was latent from the original `NavigationSplitView` adoption. Phase 8B is
the first phase where a user-triggered push navigation is exercised from the
detail column (the "Replay Workout" button), so the regression surfaces now.

## Chosen Fix

Wrap the conditional content inside the `NavigationSplitView` `detail:` closure
with a path-bound `NavigationStack`. A focused `DetailNavigationState` owns the
typed replay route and selection-reset behavior. `WorkoutDetailView` invokes an
`onReplay` callback that appends the selected workout ID to that path:

```swift
} detail: {
    NavigationStack(path: $detailNavigation.path) {
        if ... {
            emptyState
        } else if ... {
            WorkoutDetailView(onReplay: {
                detailNavigation.showReplay(workoutID: detail.id)
            })
        } else {
            DashboardView(...)
        }
    }
    .navigationDestination(for: DetailNavigationState.Route.self) { ... }
    .onChange(of: selectedWorkoutID) {
        detailNavigation.resetForSelectionChange()
    }
}
```

**Why `NavigationStack` inside `detail:` and not on each sub-view:**
Placing it at the `detail:` level ensures all content views can use
`.navigationDestination` and `.navigationTitle` correctly. Owning the route in
`ContentView` also gives sidebar selection and replay presentation one source
of truth: selecting another workout clears the path and dismisses Replay.

## Affected Files

| File | Change |
|---|---|
| `Sources/RowPlayStudio/Views/DetailNavigationState.swift` | Own the typed replay path and selection-reset behavior |
| `Sources/RowPlayStudio/Views/ContentView.swift` | Bind the detail stack to the navigation state and render destinations |
| `Sources/RowPlayStudio/Views/WorkoutDetailView.swift` | Request replay navigation through an injected callback |

No changes to `ReplayView` or `ReplayState`.

## Accessibility

- The back button rendered by `NavigationStack` is keyboard-accessible
  (Cmd+left or Escape) and VoiceOver-compatible by default.
- No additional accessibility work required for this fix.

## Regression Test Strategy

SwiftPM XCTest cannot simulate UI clicks on SwiftUI views. The regression test
operates at the boundary below the UI layer:

1. **ReplayView instantiation**: Verify that `ReplayView(detail:)` can be
   constructed from demo `WorkoutDetail` data without crashing. This catches
   any initialization issue that would silently fail a push.
2. **ReplayState initialisation**: Verify that `ReplayState(strokes:)` can be
   constructed from demo workout strokes with valid duration and paused state.
3. **Navigation state**: Verify the production navigation state routes the
   selected workout and clears the replay route when sidebar selection changes.

The boundary is: tests cover production route transitions and replay view/state
construction, while `swift build` verifies the SwiftUI navigation structure.
SwiftPM XCTest cannot simulate the actual SwiftUI button click without an
external UI-inspection dependency.
