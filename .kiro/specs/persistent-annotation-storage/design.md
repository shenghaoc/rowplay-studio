# Persistent Annotation Storage Design

## Architecture

`SQLiteAnnotationStore` is a pure `RowPlayCore` type. It conforms to the
existing `AnnotationStore` protocol and uses `SQLite3` C API directly, matching
the pattern established by `SQLiteWorkoutCache`.

Annotations live in a **separate** `annotations.sqlite` database under
`Application Support/RowPlayStudio/`. This avoids coupling annotation schema
evolution with the workout cache and keeps the workout-cache schema unchanged.

`AnnotationStoreFactory` is a `RowPlayStudio`-level type (not `RowPlayCore`)
that resolves the Application Support path, opens the database, and returns
the store. It handles errors by logging through `PrivacySafeLogger` and
falling back to `UnavailableAnnotationStore`.

## Database Design

The v1 schema uses a single `annotations` table with an auto-increment primary
key and a composite index for efficient per-workout ordered reads:

```sql
CREATE TABLE IF NOT EXISTS annotations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL,
    timestamp REAL NOT NULL,
    text TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_annotations_workout_timestamp
    ON annotations (workout_id, timestamp, id);
```

`PRAGMA user_version` tracks schema version (v1). Migration runs atomically
inside a transaction and is idempotent — calling it on an already-migrated
database returns immediately.

## Threading Model

All database access is serialized through a private `DispatchQueue`, identical
to `SQLiteWorkoutCache`. The class is `@unchecked Sendable`.

The initializer opens the database and runs migration synchronously on the
calling thread. All protocol methods dispatch to the serial queue.

## Semantics Preservation

The SQLite implementation preserves `InMemoryAnnotationStore` semantics exactly:

- `id == 0` → INSERT, return the auto-generated rowid
- `text` → trimmed before validation and persistence
- Update → preserves original `createdAt` from the existing row
- Update with wrong `workoutId` → `AnnotationError.notFound`
- Load → `ORDER BY timestamp ASC, id ASC`
- Delete missing → no-op (no error)
- `deleteAll` → `DELETE FROM annotations` + `DELETE FROM sqlite_sequence WHERE name='annotations'`

## Error Strategy

`AnnotationError` gains two new cases:

- `storageUnavailable` — the database cannot be opened or operated on at all
- `storageFailed(String)` — a specific operation failed; the string is a
  privacy-safe diagnostic (no user content)

`UnavailableAnnotationStore` is a sentinel that throws `storageUnavailable` for
every method. Production code never silently falls back to in-memory storage.

## Disconnect Cleanup

`Concept2SyncController.disconnect` now independently tracks:

1. Token deletion failure
2. Workout cache cleanup failure
3. Annotation store cleanup failure

The final status message is "Concept2 token deleted; local data cleanup failed."
if any of the three cleanup steps fail. The in-memory workout state is always
cleared regardless of cleanup failures.

## Key Differences from SQLiteWorkoutCache

| Aspect | SQLiteWorkoutCache | SQLiteAnnotationStore |
| --- | --- | --- |
| Database file | `workouts.sqlite` | `annotations.sqlite` |
| Migration | Explicit `migrate()` call | Automatic in `init` |
| Schema version tracking | `PRAGMA user_version` | `PRAGMA user_version` |
| Concurrency | Serial `DispatchQueue` | Serial `DispatchQueue` |
| Flags | `SQLITE_OPEN_FULLMUTEX` | `SQLITE_OPEN_FULLMUTEX` |

The automatic migration in `init` is a deliberate design choice: `AnnotationStore`
is a simple protocol with no migration method, and annotation callers should not
need to know about schema management.
