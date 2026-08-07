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
- [ ] 8. Manual three-sport repro in the staged app: select the 2000m RowErg
      test, open its replay, go back, select the 1000m SkiErg, press ⇧⌘P
      immediately, and confirm the SkiErg replay opens; repeat for the 8000m
      BikeErg and back to RowErg. Also confirm "Replay Workout" appears in the
      Workout menu with ⇧⌘P and greys out with an accurate reason on the
      stroke-less 5000m steady row.

      **Not yet performed.** Screen-control permission for the staged app was
      declined, so this must be run by a human before merge. Nothing else in
      this spec is outstanding.
