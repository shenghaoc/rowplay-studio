# Phase 2 Design: Native Dashboard and Library

## Goal

Port the web app's `workoutQuery.ts` pure query/filter/sort engine into `RowPlayCore`, wire it into the native `WorkoutLibrary` store, and upgrade the sidebar and dashboard to use it. All dashboard calculations must come from `RowPlayCore`, not view-local math.

## Architecture

### 1. WorkoutQuery Engine (`RowPlayCore/Library/WorkoutQuery.swift`)

A pure, testable module porting the web app's `workoutQuery.ts`:

- `WorkoutSortField` enum matching web: `date`, `distance`, `time`, `pace`, `power`.
- `SortDir` enum: `asc`, `desc`.
- `WorkoutListQuery` value type holding all filter/sort state.
- `WorkoutQuery` enum namespace with static methods:
  - `filterAndSortWorkouts(_:query:pbIds:)` — the main filter+sort pipeline.
  - `toggleDistanceChip(_:metres:)` — toggle distance chip.
  - `toggleDurationChip(_:seconds:)` — toggle duration chip.
  - `avgPowerWatts(for:)` — compute average watts.
  - `pbWorkoutIds(workouts:)` — PB workout IDs at standard distances.
- `DistanceChip` and `DurationChip` constants matching web's `DISTANCE_CHIPS` and `DURATION_CHIPS`.

### 2. WorkoutLibrary Store Updates (`Sources/RowPlayStudio/Stores/WorkoutLibrary.swift`)

- Add `@Published var query: WorkoutListQuery` with default sort=date, dir=desc.
- Replace `filteredDetails` computed property with `WorkoutQuery.filterAndSortWorkouts` call.
- Add computed `pbIds: Set<Int>` and `availableWorkoutTypes: [String]`.
- Remove the old `selectedSport` and `searchText` properties (consolidated into `query`).

### 3. SidebarView Enhancements (`Sources/RowPlayStudio/Views/SidebarView.swift`)

- Toolbar: sort picker, sport segmented picker.
- Row: show PB badge, compact date/distance/time/pace.
- Use `library.query` binding instead of separate sport/search state.

### 4. ContentView Updates (`Sources/RowPlayStudio/Views/ContentView.swift`)

- Wire `library.query` into the toolbar sport picker and searchable modifier.
- Remove separate `selectedSport` picker (now in sidebar or unified).

### 5. DashboardView Enhancements (`Sources/RowPlayStudio/Views/DashboardView.swift`)

- Add PB highlights section showing each standard-distance PB.
- Add per-sport summary cards.
- All data from `RowPlayCore` analytics, no view-local computation.

## File Layout

```
Sources/RowPlayCore/
  Library/
    WorkoutQuery.swift              (new)
Sources/RowPlayStudio/
  Stores/
    WorkoutLibrary.swift            (modify)
  Views/
    ContentView.swift               (modify)
    SidebarView.swift               (modify)
    DashboardView.swift             (modify)
    MetricTile.swift                (existing, no changes)
Tests/RowPlayCoreTests/
  WorkoutQueryTests.swift           (new)
```

## Non-Goals

- No Concept2 sync, Keychain, SQLite, or network code.
- No replay renderer, Bluetooth, calendar/heatmap, or PMC.
- No file import/export (depends on later phases).
