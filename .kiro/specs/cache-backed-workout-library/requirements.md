# Cache-Backed Workout Library — Requirements

## Purpose

Make the native workout library load workouts from `WorkoutCache` (SQLite), with demo data available only as a demo-mode fallback.

## User Stories

1. As a user who has synced Concept2 workouts, I want the app to show my synced workouts on launch without manual intervention.
2. As a user exploring the app without a Concept2 token, I want demo mode to show sample workouts on launch so I can evaluate the app.
3. As a user with demo mode disabled and no synced workouts, I want an honest empty state rather than stale demo data.
4. As a developer, I want the library data source to be testable without SwiftUI dependencies.

## Requirements

### R1: Cache-First Loading

- The workout library MUST load workouts from `WorkoutCache` when cached data is available.
- Cached workouts MUST take priority over demo data, even when demo mode is enabled.
- Launch cache hydration MUST NOT require a stored Concept2 token, because reading cache/demo/empty state is local-only.

### R2: Demo Mode Fallback

- When the cache is empty AND `demoModeEnabled` is true, the library MUST load demo workouts from `DemoWorkoutLibrary`.
- When the cache is empty AND `demoModeEnabled` is false, the library MUST show an empty state.
- Demo data MUST NOT be shown silently when `demoModeEnabled` is false.

### R3: Error Handling

- Cache failures MUST propagate as errors to the caller.
- Cache failures MUST NOT silently fall back to demo data.
- The library MUST NOT mutate or delete cache rows during normal load operations.

### R4: Reload Behavior

- Calling reload MUST re-evaluate the cache → demo → empty rules.
- Reloading MUST replace existing library data with the fresh load result.
- Manual Concept2 sync MUST trigger a library reload from cache.
- Manual Concept2 sync MUST NOT persist demo mode as disabled until the post-sync cache reload succeeds.

### R5: Batch Detail Loading

- Loading cache-backed library details MUST use a batch detail API rather than one async detail query per workout.
- `SQLiteWorkoutCache` MUST implement the batch detail API without dispatching once per workout.
- Missing detail rows in a batch MUST still produce placeholder details with empty strokes and splits.

### R6: Testability

- The loader MUST be a pure `RowPlayCore` type with no SwiftUI or AppKit dependencies.
- The loader MUST accept a `WorkoutCache` and `demoModeEnabled` flag.
- Tests MUST use `InMemoryWorkoutCache` or a throwing fake.

### R7: Non-Goals

- No new Concept2 API endpoints.
- No SQLite schema changes.
- No background sync.
- No Bluetooth or hardware changes.
- No UI redesign.
- No removal of demo fixtures.
