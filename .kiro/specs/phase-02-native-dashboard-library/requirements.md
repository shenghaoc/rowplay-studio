# Phase 2 Requirements: Native Dashboard and Library

## R1: Workout Query Engine

The native app must port the web app's `workoutQuery.ts` pure query/filter/sort engine into `RowPlayCore` so dashboard calculations never use view-local math.

- **R1.1** `WorkoutSortField` enum: `date`, `distance`, `time`, `pace`, `power`.
- **R1.2** `SortDir` enum: `asc`, `desc`.
- **R1.3** `WorkoutListQuery` struct captures all filter/sort state: sport, workoutType, dateFrom, dateTo, distanceM, hasStroke, searchText, pbsOnly, durationMin, durationMax, sort, dir.
- **R1.4** `WorkoutQuery.filterAndSortWorkouts(_:query:pbIds:)` applies every filter field and returns sorted results.
- **R1.5** Distance chip constants: 500, 2000, 5000, 10000, 42195 metres with ±2% tolerance matching.
- **R1.6** Duration chip constants: 1200, 1800, 3600 seconds with ±10% tolerance matching.
- **R1.7** `toggleDistanceChip` and `toggleDurationChip` toggle chips on/off (clearing the other chip type).
- **R1.8** `avgPowerWatts` computes average watts from `wattMinutes` and `time`.
- **R1.9** `WorkoutQuery.pbWorkoutIds` returns the set of workout IDs that are PBs at standard distances, matching the existing `PersonalBests.distancePBs` logic.

## R2: WorkoutLibrary Store Improvements

- **R2.1** `WorkoutLibrary` gains a `@Published var query: WorkoutListQuery` property with sensible defaults (sort by date descending).
- **R2.2** `filteredDetails` uses `WorkoutQuery.filterAndSortWorkouts` instead of view-local filtering.
- **R2.3** `WorkoutLibrary` exposes cached `pbIds: Set<Int>` from the current workouts and active sport filter.
- **R2.4** `WorkoutLibrary` exposes `availableWorkoutTypes: [String]` derived from the loaded workouts.

## R3: Enhanced Sidebar

- **R3.1** Sidebar toolbar includes a sort picker (date, distance, time, pace, power).
- **R3.2** Sidebar toolbar includes a segmented sport picker (All, RowErg, SkiErg, BikeErg).
- **R3.3** Sidebar list shows PB badge on workouts that hold a standard-distance PB.
- **R3.4** Sidebar row shows date, distance, time, pace in a compact layout.
- **R3.5** Keyboard selection works: arrow keys navigate the list, Enter selects, Escape clears.

## R4: Enhanced Dashboard

- **R4.1** Dashboard shows summary metrics: sessions, total distance, challenge distance, total time, average pace.
- **R4.2** Dashboard shows per-sport summary cards with distance, sessions, best pace.
- **R4.3** Dashboard shows personal bests section listing each standard-distance PB with time and date.
- **R4.4** Dashboard metric and collection derivations use `RowPlayCore` analytics/query helpers exclusively; SwiftUI views only render the provided values.

## R5: Test Coverage

- **R5.1** `WorkoutQueryTests` covers: filter by sport, filter by date range, filter by distance chip, filter by duration chip, filter by search text, filter by PBs-only, sort by each field ascending/descending, toggle chips on/off, empty result handling.
- **R5.2** `swift test` passes.
- **R5.3** `swift build` passes.

## R6: Non-Goals

- No Concept2 sync, Keychain, SQLite, or network code.
- No replay renderer or Bluetooth connectivity.
- No calendar/heatmap or PMC (Phase 2 scope is narrowed to query engine + library UX).
