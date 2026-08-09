# Tasks: Replay Command Targets the Current Selection

- [x] 1. Add the replay availability policy and a selection-resolving push to
      `DetailNavigationState`, consulted by both the disabled state and the
      push.
- [x] 2. Add the `ReplayCommand` focused-value type with per-reason help copy.
- [x] 3. Publish the command from `ContentView` and resolve the selection at
      invocation time instead of capturing a workout ID.
- [x] 4. Add the "Replay Workout" item with ⇧⌘P to the Workout command menu and
      remove the shortcut from the toolbar item.
- [x] 5. Add regression coverage for stale-closure targeting across all three
      sports, availability/push agreement, and command enablement.
- [x] 6. Run `swift build`, `swift test`, and `git diff --check`, including
      `-Xswiftc -warnings-as-errors` as CI runs them.
- [x] 7. Stage and launch the app: `./script/build_and_run.sh --verify`.
- [x] 8. Manual three-sport repro in the staged app: select the 2000m RowErg
      test, open its replay, go back, select the 1000m SkiErg, press ⇧⌘P
      immediately, and confirm the SkiErg replay opens; repeat for the 8000m
      BikeErg and back to RowErg. Also confirm "Replay Workout" appears in the
      Workout menu with ⇧⌘P and greys out with an accurate reason on the
      stroke-less 5000m steady row.

      **Performed 2026-08-10 on the staged bundle.** Every switch was followed
      by ⇧⌘P with no settling delay:

      | Step | Result |
      |---|---|
      | 2000m test (RowErg) → ⇧⌘P | RowErg replay, water and shell |
      | → 1000m SkiErg → ⇧⌘P | SkiErg replay, snow, 42 spm |
      | → 8000m BikeErg → ⇧⌘P | BikeErg replay, velodrome, 85 rpm |
      | → 2000m test (RowErg) → ⇧⌘P | RowErg replay |
      | Workout menu | "Replay Workout ⇧⌘P" present, enabled, above the divider |
      | 5000m steady, 15 Jan 24 (no strokes) | Menu item and toolbar button both greyed; ⇧⌘P a safe no-op |
      | Toolbar button after selecting SkiErg | Opened the SkiErg replay, not the previous selection |
