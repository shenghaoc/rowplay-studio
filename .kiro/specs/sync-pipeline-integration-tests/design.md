# Sync Pipeline Integration Tests — Design

## Approach

Tests exercise the real production types (`WorkoutSyncCoordinator`, `SQLiteWorkoutCache`, `WorkoutLibraryLoader`) with only the Concept2 API client faked. Each test creates a fresh temporary SQLite database file and cleans it up in `tearDown`.

## Test Fakes

### FakeConcept2Client

A `Concept2APIClient` that holds a fixed array of `WorkoutDetail` values and returns them from `fetchWorkouts` / `fetchWorkoutDetail`. Uses `DemoWorkoutLibrary.details` subsets or hand-built minimal details. Tracks call counts for diagnostics. No URLSession, no network, no token.

### FailingConcept2Client

A `Concept2APIClient` that always throws from `fetchWorkouts`. Used to verify that sync failure preserves existing cache data and that error messages are privacy-safe.

### SelectiveFailureClient

A `Concept2APIClient` that returns a fixed summary list but throws from `fetchWorkoutDetail` for selected workout IDs. Used to verify that partial detail failures are counted without saving the failed workout.

### Real types used

- `SQLiteWorkoutCache` with a unique temp `.db` path per test.
- `WorkoutSyncCoordinator` with the fake client and real cache.
- `WorkoutLibraryLoader` with the real cache.

## Test Matrix

| # | Test | Cache state | Client behavior | Expected |
|---|------|-------------|-----------------|----------|
| 1 | Pipeline writes cache and library loads | Empty | Returns 2 details | Source=cache, 2 workouts |
| 2 | Pipeline works with demo disabled | Empty | Returns 1 detail | Source=cache, 1 workout |
| 3 | Empty cache + demo disabled | Empty | N/A | Source=empty, 0 details |
| 4 | Empty cache + demo enabled | Empty | N/A | Source=demo, demo count |
| 5 | Repeated sync no duplicates | Empty | Returns same 2 details × 2 syncs | Still 2 unique workouts |
| 6 | Persists across cache instances | Empty | Returns 2 details | Second instance loads same data |
| 7 | Client failure preserves cache | Seeded 1 detail | Throws | Source=cache, seeded detail intact |
| 8 | Partial failure continues with real SQLite | Empty | Returns 3 summaries; one detail throws | 2 saved, 1 failed, failed ID absent |
| 9 | Errors don't expose token | Empty | Throws with secret in message | Error string omits secret |

## Bug Fix Rules

If tests expose a real bug, fix only the smallest related area in:
- `Sources/RowPlayCore/Sync/*`
- `Sources/RowPlayCore/Storage/*`
- `Sources/RowPlayCore/Library/*`
- `Sources/RowPlayCore/Concept2/*` (only if the fake/test protocol requires it)

Do not add UI, new features, new schema (unless a test exposes a real bug), real network behavior, or Bluetooth code.
