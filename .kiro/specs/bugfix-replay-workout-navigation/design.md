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
with a `NavigationStack`. This is the canonical SwiftUI pattern:

```swift
} detail: {
    NavigationStack {
        if ... {
            emptyState
        } else if ... {
            WorkoutDetailView(...)
        } else {
            DashboardView(...)
        }
    }
}
```

**Why `NavigationStack` inside `detail:` and not on each sub-view:**
Placing it at the `detail:` level ensures all content views can use
`.navigationDestination` and `.navigationTitle` correctly. It also provides a
single consistent navigation context for the entire detail column.

## Affected Files

| File | Change |
|---|---|
| `Sources/RowPlayStudio/Views/ContentView.swift` | Wrap `detail:` content in `NavigationStack` |

No changes to `WorkoutDetailView`, `ReplayView`, or `ReplayState`.

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
3. **NavigationStack presence**: `NavigationStack` is structurally present in
   `ContentView`'s detail column (compile-time guarantee, no runtime test
   needed — the view hierarchy is verified by `swift build`).

The boundary is: we test that the navigation-action state and view construction
are correct, and that `NavigationStack` is structurally present. We cannot test
that SwiftUI's runtime push actually fires — that requires UI-test or manual
verification.
