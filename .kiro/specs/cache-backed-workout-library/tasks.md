# Cache-Backed Workout Library — Tasks

## Implementation Tasks

- [ ] Create `WorkoutLibrarySource` enum in `Sources/RowPlayCore/Library/`.
- [ ] Create `WorkoutLibrarySnapshot` struct in `Sources/RowPlayCore/Library/`.
- [ ] Create `WorkoutLibraryLoader` enum with `load(cache:demoModeEnabled:)` in `Sources/RowPlayCore/Library/`.
- [ ] Update `WorkoutLibrary` to add `librarySource` property and `loadFromSource` method.
- [ ] Update `Concept2SyncController` to use `library.loadFromSource` for cache hydration and post-sync reload.
- [ ] Update `RowPlayStudioApp` to start with empty library and rely on `loadFromSource`.
- [ ] Create `WorkoutLibraryLoaderTests` with 6 required test cases.
- [ ] Update `Concept2SyncControllerTests` to reflect new cache-priority behavior.
- [ ] Update `docs/source-map.md` with new library loader entries.
- [ ] Update `docs/beta-readiness.md` to reflect cache-backed library state.

## Validation

- [ ] `swift test` passes.
- [ ] `swift build` passes.
- [ ] `git diff --check` passes.
- [ ] No SQLite schema changes.
- [ ] No new network endpoints.
- [ ] No Bluetooth files changed.
- [ ] No duplicate demo mode setting key.
- [ ] No demo data shown when demo mode is off and cache is empty.
