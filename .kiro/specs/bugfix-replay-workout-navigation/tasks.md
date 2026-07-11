# Tasks: Replay Workout Navigation Fix

- [x] 1. Wrap `NavigationSplitView` detail content in `NavigationStack` in
      `ContentView.swift`.
- [x] 2. Add regression test: verify `ReplayView` can be instantiated from
      demo workout detail data.
- [x] 3. ~~Add regression test: verify the `showingReplay` action state toggles
      correctly.~~ Removed — local-variable toggle test was redundant per review.
- [x] 4. Run full validation: `swift test`, `swift build`, `git diff --check`,
      `./script/build_and_run.sh --verify`.
- [x] 5. Commit, push, open draft PR with root cause, tests, and honestly
      unverified manual steps.
- [x] 6. Replace the split Boolean/path navigation state with a typed replay
      route owned by `ContentView`, and clear it on sidebar selection changes.
