# Phase 02 Native Dashboard And Library Tasks

- [ ] Create `WorkoutQuery.swift` with `WorkoutSortField`, `SortDir`, `WorkoutListQuery`, chip constants, and `WorkoutQuery` namespace.
- [ ] Implement `filterAndSortWorkouts` with all filter fields and sort comparators.
- [ ] Implement `toggleDistanceChip`, `toggleDurationChip`, `avgPowerWatts`, `pbWorkoutIds`.
- [ ] Add `WorkoutQueryTests.swift` covering filter, sort, chips, PBs, and edge cases.
- [ ] Update `WorkoutLibrary.swift` to use `WorkoutQuery` for filtering/sorting.
- [ ] Update `SidebarView.swift` with sort picker, sport picker, PB badge, compact rows.
- [ ] Update `ContentView.swift` to wire query bindings into toolbar.
- [ ] Update `DashboardView.swift` with PB highlights and sport summaries.
- [ ] Create `.kiro/specs/phase-02-native-dashboard-library` spec documents.
- [ ] Update `docs/source-map.md` with Phase 2 mappings.
- [ ] Update `docs/roadmap.md` Phase 2 status.
- [ ] Run `swift test` - all tests pass.
- [ ] Run `swift build` - clean build.
- [ ] Run `git diff --check` - no whitespace errors.
