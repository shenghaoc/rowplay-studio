# Cache-Backed Workout Library — Design

## Overview

Introduce a `WorkoutLibraryLoader` in `RowPlayCore` that encapsulates the cache → demo → empty fallback logic. Wire `WorkoutLibrary` to use this loader on initial load and after sync, with launch hydration independent of Concept2 token state.

## New Types

### `WorkoutLibrarySource` (enum)

Located in `Sources/RowPlayCore/Library/WorkoutLibrarySource.swift`.

```swift
public enum WorkoutLibrarySource: String, Sendable, Equatable {
    case cache
    case demo
    case empty
}
```

Tracks which data source the library loaded from.

### `WorkoutLibrarySnapshot` (struct)

Located in `Sources/RowPlayCore/Library/WorkoutLibrarySnapshot.swift`.

```swift
public struct WorkoutLibrarySnapshot: Sendable {
    public let details: [WorkoutDetail]
    public let source: WorkoutLibrarySource
}
```

Immutable snapshot returned by the loader.

### `WorkoutLibraryLoader` (enum)

Located in `Sources/RowPlayCore/Library/WorkoutLibraryLoader.swift`.

```swift
public enum WorkoutLibraryLoader {
    public static func load(
        cache: WorkoutCache,
        demoModeEnabled: Bool
    ) async throws -> WorkoutLibrarySnapshot
}
```

Logic:
1. Call `cache.migrate()`.
2. Load all cached workout details.
3. If cache has workouts → return `.cache` snapshot.
4. If cache is empty and `demoModeEnabled` → return `.demo` snapshot with `DemoWorkoutLibrary.details`.
5. If cache is empty and not `demoModeEnabled` → return `.empty` snapshot.
6. Cache errors propagate as thrown exceptions.

### `WorkoutCache.details(for:)`

Located in `Sources/RowPlayCore/Sync/WorkoutCache.swift`.

```swift
func details(for ids: [Workout.ID]) async throws -> [Workout.ID: WorkoutDetail]
```

The protocol extension supplies a compatibility fallback that loops through
`detail(id:)`. `InMemoryWorkoutCache` and `SQLiteWorkoutCache` override it.
`SQLiteWorkoutCache` performs batch `SELECT id, detail_json ... WHERE id IN (...)`
queries inside one serialized database operation, chunked to stay below SQLite
parameter limits.

## Modified Types

### `WorkoutLibrary`

- Add `private(set) var librarySource: WorkoutLibrarySource` property.
- Add `func loadFromSource(cache: WorkoutCache) async throws` that calls the loader using the library's persisted demo-mode state and applies the snapshot.
- Add `func loadSyncedSource(cache: WorkoutCache) async throws` for manual sync completion. It loads with demo fallback disabled, applies the cache/empty snapshot, then persists demo mode off only after the reload succeeds.
- Keep `WorkoutLibrary.demo()` factory for backward compatibility.
- Keep existing demo mode notification handler unchanged (it manages the demo overlay on top of existing data).

### `Concept2SyncController`

- `loadCachedWorkouts(into:)`: call `library.loadFromSource(cache:)` even when no token is stored, because local cache/demo loading does not need network auth.
- `loadCachedWorkouts(into:)`: set the "Loaded N cached workouts" status only when `library.librarySource == .cache`.
- `syncNow(into:)`: after sync completes, call `library.loadSyncedSource(cache:)` instead of `library.replaceWithSyncedDetails(details)`.
- Remove private `loadDetails(from:)` helper (logic moved to loader).

### `RowPlayStudioApp`

- Change `WorkoutLibrary.demo()` to `WorkoutLibrary(details: [])` since `loadFromSource` handles the demo fallback.
- Keep the `.task` that calls `loadCachedWorkouts`.

## Data Flow

### App Launch

```
RowPlayStudioApp.init
  → WorkoutLibrary(details: [])
  → .task { syncController.loadCachedWorkouts(into: library) }
    → resolved SQLite cache (no token required)
    → library.loadFromSource(cache)
      → WorkoutLibraryLoader.load(cache, library.demoModeEnabled)
        → cache.migrate()
        → cache.listWorkouts()
        → if has workouts: cache.details(for: ids), then return .cache snapshot
        → if empty + demo: return .demo snapshot
        → if empty + !demo: return .empty snapshot
      → library.details = snapshot.details
      → library.librarySource = snapshot.source
```

### Manual Sync

```
User triggers sync
  → syncController.syncNow(into: library)
    → coordinator.syncAll() → saves to cache
    → library.loadSyncedSource(cache)
      → loads from cache without demo fallback
      → applies cache/empty snapshot
      → disables demo mode only after successful reload
```

### Demo Mode Toggle

```
User toggles demoModeEnabled in Settings
  → UserDefaults.didChangeNotification
  → library.updateDemoModeState()
    → if enabled: append missing demo details
    → if disabled: remove demo details by ID
```

## Test Strategy

`WorkoutLibraryLoaderTests` in `Tests/RowPlayCoreTests/Library/`:

1. Cache has data → returns cache source and cache details.
2. Cache empty + demo enabled → returns demo source and demo details.
3. Cache empty + demo disabled → returns empty source and empty details.
4. Cache has data + demo enabled → cache takes priority.
5. Cache throws → error propagates, no silent demo fallback.
6. Source enum values are stable.
7. Loader uses `details(for:)` batch lookup.
8. Startup loads demo fallback without a token when demo mode is enabled.
9. Startup remains empty without a token when demo mode is disabled.
10. Demo fallback does not show a misleading "cached workouts" status.
11. Post-sync cache reload failure preserves the user's demo-mode preference.
