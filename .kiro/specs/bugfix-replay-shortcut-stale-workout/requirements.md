# Bugfix: Replay Command Targets the Previously Selected Workout

## Regression

Triggering "Replay Workout" frequently opens the replay of the *previously*
selected workout instead of the one shown in the detail pane. The wrong sport
scene loads and the transport HUD shows the wrong pace.

Reproduction (reliable in demo mode):

1. Select workout A (2000m test, RowErg) and open its replay.
2. Go back, then select workout B in the sidebar (1000m SkiErg or 8000m
   BikeErg).
3. Wait until the detail pane header clearly shows workout B.
4. Press ⇧⌘P.

The replay that opens is workout A's. Waiting five or more seconds sometimes
makes the shortcut target the right workout, and sometimes does not — the
behavior is timing-dependent, which is what makes it look intermittent.

This is distinct from [`bugfix-replay-workout-navigation`](../bugfix-replay-workout-navigation/requirements.md),
which fixed replay not pushing *at all*. That fix is still correct and remains
in place; this spec covers the replay pushing the *wrong workout*.

## Scope

- **In scope**: Resolve the replay target from the live selection at the moment
  the command fires; move the ⇧⌘P shortcut to a menu-bar command; keep the
  detail toolbar button working; report honest disabled reasons.
- **Out of scope**: `ReplayView` internals, `ReplayState`, rig or scene code,
  sidebar selection storage, and the pre-existing ⌘1 Dashboard shortcut.

## Acceptance Criteria

1. After switching sidebar selection, ⇧⌘P opens the replay of the workout
   currently shown in the detail pane — with no settling delay — for RowErg,
   SkiErg, and BikeErg.
2. The detail toolbar "Replay Workout" button obeys the same rule.
3. "Replay Workout" appears in the Workout menu with the ⇧⌘P shortcut, making
   the shortcut discoverable per the macOS Human Interface Guidelines.
4. The menu item is disabled, with an accurate reason, when the library is
   loading, nothing is selected, the selected workout has no stroke data, or a
   replay is already open.
5. The menu item's enabled state always matches what invoking the command
   actually does — the disabled state and the push consult one policy.
6. Repeated invocation never stacks a second replay route.
7. Regression coverage proves an action closure created while workout A was
   selected pushes workout B's route after the selection changes.
8. `swift test` and `swift build` pass, including with
   `-Xswiftc -warnings-as-errors` as CI runs them.

## Non-Goals

- Re-architecting navigation or the selection model.
- Adding menu items or shortcuts beyond the replay command.
- Changing replay playback, camera, rival, or rendering behavior.
