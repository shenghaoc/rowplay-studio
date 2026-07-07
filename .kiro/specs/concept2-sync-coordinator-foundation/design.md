# Concept2 Sync Coordinator Foundation — Design

## Architecture

```
WorkoutSyncCoordinator
    ↓ (depends on protocols)
Concept2APIClient (existing)    WorkoutCache (existing)
    ↑                               ↑
MockConcept2Client              InMemoryWorkoutCache / SQLiteWorkoutCache
```

## Components

### WorkoutSyncState

Lightweight enum for coordinator-level sync status:

```swift
public enum WorkoutSyncState: Equatable, Sendable {
    case idle
    case syncing
    case completed(WorkoutSyncResult)
    case failed(WorkoutSyncError)
}
```

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

Privacy rule: associated `String` values must not contain tokens, headers, or payloads. Use `redact()` when wrapping underlying error descriptions.

### WorkoutSyncCoordinator

```swift
public final class WorkoutSyncCoordinator: @unchecked Sendable {
    public init(client: Concept2APIClient, cache: WorkoutCache)
    public func syncAll() async throws -> WorkoutSyncResult
}
```

## Sync Flow

1. Record `startedAt`.
2. Page through `client.fetchWorkouts(page:perPage:)` until all pages are consumed (250 per page, matching the API max and web app's `listWorkoutsPage`).
3. Collect all `Workout` summaries.
4. For each summary, call `client.fetchWorkoutDetail(id:)`.
5. On success, call `cache.save(detail:)` and increment `savedCount`.
6. On failure (client or cache), log via `PrivacySafeLogger`, increment `failedCount`, and continue.
7. Record `finishedAt` and return `WorkoutSyncResult`.

Fundamental failures (e.g., the initial `fetchWorkouts` call fails entirely) throw `WorkoutSyncError` rather than returning a partial result.

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
- `InMemoryWorkoutCache`: existing in-memory cache for success-path tests.
- No real network, no real tokens, no sleeps.
- Tests verify: correct counts, partial failure tolerance, idempotency, error privacy, no real network usage.
