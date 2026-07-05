# SQLite Workout Cache Foundation — Design

## Architecture

### File Layout

```
Sources/RowPlayCore/Sync/WorkoutCache.swift           # Existing protocol (extended)
Sources/RowPlayCore/Storage/WorkoutCacheError.swift    # New error enum
Sources/RowPlayCore/Storage/SQLiteWorkoutCache.swift   # New SQLite implementation
Sources/RowPlayCore/Storage/SQLiteWorkoutCacheMigration.swift  # New migration logic
Tests/RowPlayCoreTests/Storage/SQLiteWorkoutCacheTests.swift  # New tests
```

### Protocol Shape

The existing async `WorkoutCache` protocol is extended to support the storage-foundation surface from the implementation prompt:

- `migrate() throws` — ensure the backing store is ready
- `save(detail: WorkoutDetail) async throws` — save one full detail
- `save(details: [WorkoutDetail]) async throws` — save many full details
- `listWorkouts() async throws -> [Workout]` — list summaries newest first
- `detail(id: Workout.ID) async throws -> WorkoutDetail?` — load one full detail
- `delete(id: Workout.ID) async throws` — delete a single workout
- `deleteAll() async throws` — clear all cached rows

Legacy Phase 4 method names (`saveDetail`, `saveWorkouts`, `loadAllWorkouts`, `loadWorkout`) remain available as compatibility wrappers for existing call sites.

### SQLite Schema (v1)

```sql
CREATE TABLE IF NOT EXISTS workouts (
    id INTEGER PRIMARY KEY,
    sport TEXT NOT NULL,
    date REAL NOT NULL,
    workout_type TEXT NOT NULL,
    distance REAL NOT NULL,
    time REAL NOT NULL,
    pace REAL NOT NULL,
    stroke_rate REAL,
    stroke_count INTEGER,
    heart_rate_avg INTEGER,
    calories_total INTEGER,
    watt_minutes REAL,
    drag_factor INTEGER,
    comments TEXT,
    source TEXT,
    verified INTEGER NOT NULL DEFAULT 1,
    has_stroke_data INTEGER NOT NULL DEFAULT 0,
    is_interval INTEGER NOT NULL DEFAULT 0,
    detail_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts (date DESC);
```

**Why JSON in detail_json?**

This PR is a foundation. Summary columns store the complete `Workout` shape needed by `listWorkouts()` so the newest-first list can avoid decoding full detail JSON for every row. The JSON column stores the full `WorkoutDetail` for later dashboard/replay use. Normalizing strokes and splits into separate tables is deferred to a future PR if query performance or storage size requires it.

### Migration Strategy

- Uses `PRAGMA user_version` for version tracking.
- `migrate()` is idempotent: runs `CREATE TABLE IF NOT EXISTS`, adds any missing v1 summary columns via `PRAGMA table_info`, creates `idx_workouts_date`, and sets `user_version = 1`.
- Opening a cache does **not** auto-migrate. The caller must call `migrate()` explicitly.
- This prevents accidental data loss from schema changes.

### Query Shape

- `listWorkouts()` returns all cached workout summaries newest first using the summary columns and `idx_workouts_date`.
- Pagination is a future API candidate if local caches grow enough that returning every summary row creates memory pressure.
- `detail(id:)` decodes the full `WorkoutDetail` JSON for the selected workout.

### JSON Encoding

- `JSONEncoder` with `.iso8601` date strategy and `.convertToSnakeCase` keys.
- `JSONDecoder` with matching strategies.
- All model types (`WorkoutDetail`, `Workout`, `Stroke`, `Split`, `HeartRateDetail`, `Sport`) are `Codable`.
- Encoding/decoding failures throw `WorkoutCacheError.encodingFailed` / `.decodingFailed`.

### Thread Safety

`SQLiteWorkoutCache` is `@unchecked Sendable`. All database access is serialized through the serial `DispatchQueue`. This matches the existing `InMemoryWorkoutCache` pattern (NSLock-based).

### Error Handling

`WorkoutCacheError` is `Equatable` and covers:

- `openFailed(String)` — sqlite3_open_v2 failed
- `migrationFailed(String)` — CREATE TABLE or PRAGMA failed
- `queryFailed(String)` — INSERT, SELECT, DELETE, or BEGIN/COMMIT failed
- `encodingFailed(String)` — JSONEncoder threw
- `decodingFailed(String)` — JSONDecoder threw

Error messages include diagnostic context but never full workout payloads.

### System SQLite

Uses macOS system SQLite via `import SQLite3` with `linkedLibrary("sqlite3")` in Package.swift. No third-party dependencies.

## Non-Goals

- No Concept2 sync implementation
- No URLSession client
- No UI import/export
- No Bluetooth/hardware
- No normalized stroke/split schema
- No migration from v1 to v2 (future work)
