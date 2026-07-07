# Cache-Backed Workout Library — Design

## Overview

Introduce a `WorkoutLibraryLoader` in `RowPlayCore` that encapsulates the cache → demo → empty fallback logic. Wire `WorkoutLibrary` to use this loader on initial load and after sync.

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

## Modified Types

### `WorkoutLibrary`

- Add `private(set) var librarySource: WorkoutLibrarySource` property.
- Add `func loadFromSource(cache: WorkoutCache, demoModeEnabled: Bool) async throws` that calls the loader and applies the snapshot.
- Keep `WorkoutLibrary.demo()` factory for backward compatibility.
- Keep existing demo mode notification handler unchanged (it manages the demo overlay on top of existing data).

### `Concept2SyncController`

- `loadCachedWorkouts(into:)`: replace internal logic with `library.loadFromSource(cache:demoModeEnabled:)`.
- `syncNow(into:)`: after sync completes, call `library.loadFromSource(cache:demoModeEnabled:)` instead of `library.replaceWithSyncedDetails(details)`.
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
    → library.loadFromSource(cache, demoModeEnabled)
      → WorkoutLibraryLoader.load(cache, demoModeEnabled)
        → cache.migrate()
        → cache.listWorkouts()
        → if has workouts: return .cache snapshot
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
    → library.loadFromSource(cache, demoModeEnabled)
      → loads from cache (now has synced data)
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
