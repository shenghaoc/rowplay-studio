# Concept2 Sync Coordinator Foundation — Design

## Architecture

```
SettingsView / Workout menu
    ↓
Concept2SyncController
    ↓
WorkoutSyncCoordinator
    ↓ (depends on protocols)
Concept2APIClient               WorkoutCache
    ↑                               ↑
URLSessionConcept2Client        SQLiteWorkoutCache
MockConcept2Client              InMemoryWorkoutCache
```

## Components

### WorkoutSyncResult

Value type returned by `syncAll()`:

```swift
public struct WorkoutSyncResult: Equatable, Sendable {
    public var fetchedCount: Int    // summaries fetched from API
    public var savedCount: Int      // details successfully saved to cache
    public var failedCount: Int     // details that failed fetch or save
    public var startedAt: Date
    public var finishedAt: Date
}
```

### WorkoutSyncError

Typed errors for fundamental sync failures:

```swift
public enum WorkoutSyncError: Error, Equatable {
    case clientFailed(String)   // e.g., network error fetching summaries
    case cacheFailed(String)    // e.g., cache migration or save failure
    case mappingFailed(String)  // e.g., unexpected response shape
}
```

Privacy rule: associated `String` values must not contain tokens, headers, or payloads. The coordinator uses `redact()` before wrapping underlying errors, and `WorkoutSyncError.description` redacts associated strings again as a final guard.

### WorkoutSyncCoordinator

```swift
public final class WorkoutSyncCoordinator: Sendable {
    public init(client: Concept2APIClient, cache: WorkoutCache, perPage: Int = 250)
    public func syncAll() async throws -> WorkoutSyncResult
}
```

The coordinator is immutable and uses standard `Sendable`. It validates `perPage > 0` during initialization.

### Concept2SyncController

`Concept2SyncController` is the app-shell bridge:

- Saves BYOT access tokens through `TokenStore` only; production uses `KeychainTokenStore`.
- Opens `SQLiteWorkoutCache` under Application Support.
- Creates `URLSessionConcept2Client` only when a saved token exists.
- Runs `WorkoutSyncCoordinator.syncAll()`.
- Uses `SyncStateTracker` for in-progress, success, failure, and cached-count state.
- Loads cached `WorkoutDetail` records into `WorkoutLibrary` after a successful sync.
- On app launch, loads cached `WorkoutDetail` records into an empty `WorkoutLibrary` when a saved token exists, without contacting the network.
- Deletes the token and clears cached/library data on disconnect, migrating the cache first so a fresh SQLite cache instance can purge rows after relaunch.

The controller accepts injected token store, cache factory, and client factory so tests use fake stores, `InMemoryWorkoutCache`, and mock clients without real network calls.

## Sync Flow

1. Record `startedAt`.
2. Call `cache.migrate()` before any network work.
3. Page through `client.fetchWorkouts(page:perPage:)` until all pages are consumed (250 per page, matching the API max and web app's `listWorkoutsPage`).
4. Collect all `Workout` summaries.
5. For each summary, call `client.fetchWorkoutDetail(id:)`.
6. On success, call `cache.save(detail:)` and increment `savedCount`.
7. On per-workout client or cache failure, log via `PrivacySafeLogger`, increment `failedCount`, and continue.
8. Re-throw `CancellationError` immediately instead of treating cancellation as a per-workout failure.
9. Abort early on authentication, authorization, or rate-limit failures (`401`, `403`, `429`) to avoid amplified API pressure.
10. Record `finishedAt` and return `WorkoutSyncResult`.

Fundamental failures (e.g., the initial `fetchWorkouts` call fails entirely) throw `WorkoutSyncError` rather than returning a partial result.

## User Flow

1. User opens Settings > Concept2.
2. User enters a BYOT Concept2 access token in a `SecureField`.
3. Save Token stores the token in Keychain.
4. Sync Now or Workout > Sync Concept2 Logbook runs the coordinator.
5. A successful sync replaces demo data with real cached workouts and disables demo mode.
6. On later app launches, `RowPlayStudioApp` asks the controller to hydrate an empty library from the persisted cache.
7. Disconnect deletes the token, migrates and clears the local workout cache, and clears the in-memory library.

## Web Reference

From `src/lib/server/data.ts` `syncWorkouts()`:

- Pages through `c.listWorkoutsPage(page, from)` with `number=250`.
- Upserts summaries into D1 via `upsertWorkouts()`.
- Tracks `added` count and `newestDate`.
- Does NOT fetch detail during sync — detail is fetched on-demand via `loadWorkoutDetail()`.

The native coordinator differs: it fetches detail eagerly during sync so the cache is fully populated for offline replay.

## Test Strategy

- `FailingConcept2Client`: configurable to throw on `fetchWorkouts` or `fetchWorkoutDetail`.
- `FailingWorkoutCache`: configurable to throw on `save(detail:)`.
- `InMemoryWorkoutCache`: existing in-memory cache for success-path and app-wiring tests.
- Temporary `SQLiteWorkoutCache` files: relaunch-path tests for cache hydration and disconnect cleanup.
- No real network, no real tokens, no sleeps.
- Tests verify: correct counts, partial failure tolerance, idempotency, error privacy, cancellation propagation, auth/rate-limit aborts, migration before sync, no real network usage, token-store wiring, library replacement, launch cache hydration, and disconnect cleanup.
