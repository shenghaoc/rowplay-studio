# Tasks: Replay Workout Navigation Fix

- [x] 1. Wrap the `NavigationSplitView` detail content in a path-bound
      `NavigationStack`.
- [x] 2. Add focused `DetailNavigationState` route and selection-reset logic.
- [x] 3. Route the workout-detail replay action through the shared navigation
      state instead of view-local Boolean presentation state.
- [x] 4. Add regression coverage for route creation, sidebar reset, all demo
      sports, `ReplayView` construction, and `ReplayState` initialisation.
- [x] 5. Run full validation: `swift test`, `swift build`, `git diff --check`,
      and `./script/build_and_run.sh --verify`.
- [x] 6. Sync the final PR metadata and push the completed branch.
