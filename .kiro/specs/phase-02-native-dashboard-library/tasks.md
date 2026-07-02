# Phase 02 Native Dashboard And Library Tasks

- [x] Create `WorkoutQuery.swift` with `WorkoutSortField`, `SortDir`, `WorkoutListQuery`, chip constants, and `WorkoutQuery` namespace.
- [x] Implement `filterAndSortWorkouts` with all filter fields and sort comparators.
- [x] Implement `toggleDistanceChip`, `toggleDurationChip`, `avgPowerWatts`, `pbWorkoutIds`.
- [x] Add `WorkoutQueryTests.swift` covering filter, sort, chips, PBs, and edge cases.
- [x] Update `WorkoutLibrary.swift` to use `WorkoutQuery` for filtering/sorting.
- [x] Update `SidebarView.swift` with sort picker, sport picker, PB badge, compact rows.
- [x] Update `ContentView.swift` to wire query bindings into toolbar.
- [x] Update `DashboardView.swift` with PB highlights and sport summaries.
- [x] Create `.kiro/specs/phase-02-native-dashboard-library` spec documents.
- [x] Update `docs/source-map.md` with Phase 2 mappings.
- [x] Update `docs/roadmap.md` Phase 2 status.
- [x] Run `swift test` - all tests pass.
- [x] Run `swift build` - clean build.
- [x] Run `git diff --check` - no whitespace errors.
