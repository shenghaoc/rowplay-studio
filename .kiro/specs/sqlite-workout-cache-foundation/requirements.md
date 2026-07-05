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

The new `SQLiteWorkoutCache` must conform to the existing `WorkoutCache` protocol in `RowPlayCore/Sync/WorkoutCache.swift`. All protocol methods must be implemented.

### R2: SQLite v1 schema stores WorkoutDetail JSON

The cache stores full `WorkoutDetail` as JSON in a `detail_json` column. A `workouts` table with summary columns (id, sport, date, workout_type, distance, time, pace) plus `detail_json` and `updated_at` provides the foundation for future query support.

### R3: Migration is idempotent

`migrate()` can be called multiple times without failure. It creates the table if missing and sets `PRAGMA user_version = 1`.

### R4: Opening a cache does not silently drop data

The cache does not auto-migrate on open. Callers must explicitly call `migrate()`. This prevents accidental data loss.

### R5: deleteAll() deletes rows, not the database file

`deleteAll()` removes all rows from the workouts table but does not delete or recreate the database file.

### R6: JSON round-trip preserves all WorkoutDetail fields

`WorkoutDetail` must round-trip through JSON encoding/decoding with all fields intact: workout summary, strokes array, splits array, dates, sport values, and heart rate details.

### R7: Errors are typed and do not log payloads

`WorkoutCacheError` covers open, migration, query, encoding, and decoding failures. Error messages must not include full workout payloads.

### R8: delete(id:) removes a single workout

The cache supports deleting a single workout by ID. After deletion, `loadWorkout(id:)` returns nil for that ID and other workouts remain unaffected.

### R9: Tests cover all required behaviors

Required tests:

1. Migration creates schema (empty list after migrate)
2. Migration is idempotent (migrate twice without failure)
3. Save and load detail round-trips (id, sport, distance, time, pace, strokes, splits)
4. Save many and list sorts newest first
5. Delete removes single workout
6. DeleteAll clears rows
7. Missing detail returns nil
8. Cache persists across instances (two SQLiteWorkoutCache instances on same path)
