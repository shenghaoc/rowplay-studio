# Design: Replay Command Targets the Current Selection

## Root Cause

`ContentView` passed `WorkoutDetailView` an `onReplay` closure with the workout
ID baked in at render time:

```swift
onReplay: { detailNavigation.showReplay(workoutID: detail.id) }
```

`WorkoutDetailView` registered both the button and the ⇧⌘P shortcut on a
`ToolbarItem`. SwiftUI bridges toolbar content to `NSToolbar`, and the bridged
item's action is refreshed lazily — only when toolbar revalidation happens to
run. After a sidebar selection change, AppKit therefore kept dispatching the
closure built during an earlier render pass, still carrying the *old* workout
ID, so the replay route pushed the previous workout.

This explains every symptom: the wrong sport scene, the wrong pace in the HUD,
the inconsistent multi-second "settling" window (revalidation is event-driven,
not time-based), and why waiting sometimes never helped.

The navigation path was not at fault — `resetForSelectionChange()` was already
clearing it correctly on selection change.

## Chosen Fix

**1. Resolve the target when the command fires, not when the view renders.**
The action closure carries no workout ID. `ContentView.requestReplayForCurrentSelection()`
reads the selection and library through live property-wrapper storage at
invocation time, so even a closure captured during an earlier render pass
resolves the workout that is selected right now:

```swift
private func requestReplayForCurrentSelection() {
    detailNavigation.showReplay(
        for: selectedDetail,
        isLibraryLoading: syncController.isLoading
    )
}
```

This makes correctness independent of *when* AppKit captured the closure, which
is the property the old code lacked.

**2. Move ⇧⌘P to the menu bar.** A keyboard shortcut belongs in a menu on
macOS. "Replay Workout" joins the existing `Workout` command menu, separated by
a divider from the data-management items. The command reaches the menu as a
focused scene value (`ReplayCommand`), because the menu lives in the `App`
scene while the selection lives in `ContentView`. Registering the shortcut
there also takes it off the lazily-refreshing toolbar bridge entirely.

**3. One availability policy.** `DetailNavigationState.replayUnavailability(for:isLibraryLoading:)`
is consulted by both the menu item's disabled state and the push itself, so the
enabled state the user sees can never disagree with what invoking the command
does.

## Affected Files

| File | Change |
|---|---|
| `Sources/RowPlayStudio/Views/DetailNavigationState.swift` | Availability policy plus a selection-resolving `showReplay(for:isLibraryLoading:)` |
| `Sources/RowPlayStudio/App/ReplayCommand.swift` | New focused-value command type and its help copy |
| `Sources/RowPlayStudio/Views/ContentView.swift` | Publish the command; resolve the selection at invocation time |
| `Sources/RowPlayStudio/App/RowPlayStudioApp.swift` | Workout menu item owning ⇧⌘P |
| `Sources/RowPlayStudio/Views/WorkoutDetailView.swift` | Toolbar button keeps the action; the shortcut moves to the menu |

No changes to `ReplayView`, `ReplayState`, or any scene or rig code.

## Alternative Considered

Registering ⇧⌘P on a hidden zero-opacity `Button` in `ContentView`'s background
(the pattern the pre-existing ⌘1 Dashboard shortcut uses) also dodges the
toolbar bridge. It was rejected: it leaves the shortcut undiscoverable, which
the HIG treats as a defect for a primary action, and it grows `ContentView`
with UI plumbing that the menu-bar mechanism expresses natively.

## Human Interface Guidelines

- The shortcut is now discoverable in the menu bar, next to the other workout
  commands, and grouped with a divider.
- Disabled reasons are specific and actionable ("Select a workout to replay",
  "Replay requires stroke data") rather than a single generic string, and drive
  both `.help` and `.accessibilityHint`.
- The toolbar button keeps its label, symbol, tooltip, hint, and disabled
  state, so mouse users see no change.
- In acceptance mode `ContentView` is not on screen, so no command is
  published and the menu item is disabled automatically — matching the other
  Workout menu items, which are explicitly disabled in that mode.

## Regression Test Strategy

`Tests/RowPlayStudioTests/ReplayNavigationTests.swift`:

1. **Stale closure**: build the action closure while the RowErg workout is
   selected, then invoke it after switching to SkiErg, BikeErg, and back —
   asserting the pushed route matches the *new* selection each time. This is
   the bug, reproduced at the seam.
2. **Availability policy**: assert `replayUnavailability` and the push agree
   for every case (available, loading, already presented, no selection, no
   stroke data), and that an unavailable command never mutates the path.
3. **Command enablement**: assert `ReplayCommand.isEnabled` is true only when
   availability is `nil`.

**Boundary**: SwiftPM XCTest cannot simulate AppKit menu or toolbar dispatch,
so the closure-staleness property is exercised at the state seam rather than
through the real bridge, and the menu wiring itself is a compile-time
guarantee verified by `swift build`. End-to-end confirmation is the manual
repro in `tasks.md`.
