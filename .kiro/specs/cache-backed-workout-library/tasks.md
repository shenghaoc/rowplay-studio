# Cache-Backed Workout Library — Tasks

## Implementation Tasks

- [x] Create `WorkoutLibrarySource` enum in `Sources/RowPlayCore/Library/`.
- [x] Create `WorkoutLibrarySnapshot` struct in `Sources/RowPlayCore/Library/`.
- [x] Create `WorkoutLibraryLoader` enum with `load(cache:demoModeEnabled:)` in `Sources/RowPlayCore/Library/`.
- [x] Add `WorkoutCache.details(for:)` with SQLite/InMemory batch implementations.
- [x] Update `WorkoutLibrary` to add `librarySource`, `loadFromSource`, and post-sync `loadSyncedSource`.
- [x] Update `Concept2SyncController` to use `library.loadFromSource` for startup hydration and `library.loadSyncedSource` for post-sync reload.
- [x] Update `RowPlayStudioApp` to start with empty library and rely on `loadFromSource`.
- [x] Update reload menu/toolbar actions to re-run cache/demo/empty loading instead of forcing demo fixtures.
- [x] Create `WorkoutLibraryLoaderTests` with cache/demo/empty/error/source/batch coverage.
- [x] Update `Concept2SyncControllerTests` to reflect cache-priority behavior, no-token startup fallback, status messaging, and post-sync failure behavior.
- [x] Update `WorkoutLibraryDemoModeTests` so demo-mode changes are fallback-only and do not overlay fixtures on existing data.
- [x] Update `SQLiteWorkoutCacheTests` with batch detail coverage.
- [x] Update `docs/source-map.md` with new library loader entries.
- [x] Update `docs/beta-readiness.md` to reflect cache-backed library state.

## Validation

- [x] `swift test` passes.
- [x] `swift build` passes.
- [x] `git diff --check` passes.
- [x] `./script/build_and_run.sh --verify` passes.
- [x] No SQLite schema changes.
- [x] No new network endpoints.
- [x] No Bluetooth files changed.
- [x] No duplicate demo mode setting key.
- [x] No demo data shown when demo mode is off and cache is empty.
