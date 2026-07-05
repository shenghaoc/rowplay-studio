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

### Protocol Extension

The existing `WorkoutCache` protocol gets two new methods:

- `delete(id: Workout.ID) async throws` — delete a single workout
- `listWorkouts() async throws -> [Workout]` — alias for loadAllWorkouts()

`InMemoryWorkoutCache` gains implementations for both.

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
    detail_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);
```

**Why JSON in detail_json?**

This PR is a foundation. Normalizing strokes and splits into separate tables adds complexity without immediate benefit. The JSON column stores the full `WorkoutDetail` for later dashboard/replay use. Schema normalization is deferred to a future PR if query performance or storage size requires it.

### Migration Strategy

- Uses `PRAGMA user_version` for version tracking.
- `migrate()` is idempotent: runs `CREATE TABLE IF NOT EXISTS` and sets `user_version = 1`.
- Opening a cache does **not** auto-migrate. The caller must call `migrate()` explicitly.
- This prevents accidental data loss from schema changes.

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
