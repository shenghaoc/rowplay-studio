# SQLite Workout Cache Foundation — Requirements

## Problem

RowPlay Studio currently uses `InMemoryWorkoutCache` which loses all data on restart. Before real Concept2 network sync can be implemented, a persistent local storage foundation is needed.

## Scope

This PR adds a local SQLite workout cache foundation. It does **not** implement:

- Real Concept2 sync or URLSession client
- Network clients of any kind
- UI import/export workflows
- Bluetooth or hardware transport
- Normalized stroke/split tables

## Requirements

### R1: SQLiteWorkoutCache conforms to WorkoutCache protocol

The new `SQLiteWorkoutCache` must conform to the existing async `WorkoutCache` protocol in `RowPlayCore/Sync/WorkoutCache.swift`. The cache surface supports `migrate()`, `save(detail:)`, `save(details:)`, `listWorkouts()`, `detail(id:)`, `delete(id:)`, and `deleteAll()`. Legacy Phase 4 aliases remain available for existing call sites.

### R2: SQLite v1 schema stores WorkoutDetail JSON

The cache stores full `WorkoutDetail` as JSON in a `detail_json` column. A `workouts` table stores the complete `Workout` summary shape in columns, including optional metrics, comments, source, and boolean flags, plus `detail_json` and `updated_at`. `listWorkouts()` reads those summary columns directly, newest first, using a date index.

### R3: Migration is idempotent

`migrate()` can be called multiple times without failure. It creates the table if missing, adds missing v1 summary columns, creates the date index, and sets `PRAGMA user_version = 1`.

### R4: Opening a cache does not silently drop data

The cache does not auto-migrate on open. Callers must explicitly call `migrate()`. This prevents accidental data loss.

### R5: deleteAll() deletes rows, not the database file

`deleteAll()` removes all rows from the workouts table but does not delete or recreate the database file.

### R6: JSON round-trip preserves all WorkoutDetail fields

`WorkoutDetail` must round-trip through JSON encoding/decoding with all fields intact: workout summary, strokes array, splits array, dates, sport values, and heart rate details.

### R7: Errors are typed and do not log payloads

`WorkoutCacheError` covers open, migration, query, encoding, and decoding failures. Error messages must not include full workout payloads.

### R8: delete(id:) removes a single workout

The cache supports deleting a single workout by ID. After deletion, `detail(id:)` returns nil for that ID and other workouts remain unaffected.

### R9: Tests cover all required behaviors

Required tests:

1. Migration creates schema (empty list after migrate)
2. Migration is idempotent (migrate twice without failure)
3. Save and load detail round-trips (id, sport, distance, time, pace, strokes, splits)
4. Save many and list sorts newest first
5. Save summary refresh preserves existing full detail payloads
6. List reads summary columns without decoding detail JSON
7. Migration creates the date index
8. Delete removes single workout
9. DeleteAll clears rows
10. Missing detail returns nil
11. Cache persists across instances (two SQLiteWorkoutCache instances on same path)
