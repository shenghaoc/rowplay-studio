# Sync Pipeline Integration Tests — Requirements

## Purpose

Add integration tests that validate the native sync pipeline end-to-end using fake Concept2 data and a real temporary SQLite cache. These tests prove that `Concept2APIClient`, `WorkoutSyncCoordinator`, `SQLiteWorkoutCache`, and `WorkoutLibraryLoader` work together correctly before adding more production sync behavior.

## Scope

- Fake Concept2 client data flows through `WorkoutSyncCoordinator` into `SQLiteWorkoutCache`.
- `WorkoutLibraryLoader` reads synced cache data instead of falling back to demo data.
- Repeated syncs do not duplicate cached workouts.
- Cache data persists across `SQLiteWorkoutCache` instances (same temp DB file).
- Client failures do not corrupt or replace existing cached data with demo data.
- Partial detail-fetch failures continue syncing successful workouts and do not cache the failed workout.
- Sync error messages do not expose secrets or tokens.

## Non-Goals

- No real Concept2 network calls.
- No UI changes.
- No new Bluetooth/hardware code.
- No background sync behavior.
- No real BYOT tokens.
- No new SQLite schema (use existing v1 schema as-is).
- No new Concept2 API endpoints.
