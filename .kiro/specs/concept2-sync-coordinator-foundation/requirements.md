# Concept2 Sync Coordinator Foundation

## Purpose

Add a sync coordinator that bridges `Concept2APIClient` and `WorkoutCache`, then wire it into the macOS app so a user can save a Concept2 BYOT token, sync the logbook into the local cache, and load synced workouts into the native library.

## Requirements

1. **Sync coordinator**: `WorkoutSyncCoordinator` depends on `Concept2APIClient` and `WorkoutCache` protocols — no concrete implementations.
2. **Token independence**: The coordinator does not own, read, or persist tokens. Token management remains with `TokenStore` and the caller.
3. **No direct networking**: The coordinator does not import URLSession or use `HTTPTransport` directly.
4. **No direct storage**: The coordinator does not use SQLite APIs directly.
5. **Sync orchestration**: `syncAll()` pages through workout summaries, fetches detail for each workout, and saves details into the cache.
6. **Result reporting**: `WorkoutSyncResult` reports `fetchedCount`, `savedCount`, `failedCount`, `startedAt`, and `finishedAt`.
7. **Partial failure tolerance**: Individual workout detail fetch or save failures are counted and do not abort the sync.
8. **Typed errors**: `WorkoutSyncError` covers `clientFailed`, `cacheFailed`, and `mappingFailed` with privacy-safe descriptions.
9. **Privacy**: Error descriptions must not include tokens, Authorization headers, or full raw workout payloads. `redact()` must use `String(describing:)` to respect privacy-safe `CustomStringConvertible` implementations.
10. **Idempotency**: Running `syncAll()` twice with the same data produces stable cache state (no duplicate rows).
11. **Auth/rate-limit abort**: Detail fetch loops must abort early on authentication (401/403) or rate-limiting (429) errors to avoid amplified API pressure.
12. **Cancellation**: Cancellation from detail fetches or cache saves must propagate instead of being counted as a per-workout failure.
13. **Cache setup**: `syncAll()` must call `WorkoutCache.migrate()` before performing network work.
14. **App wiring**: Settings must expose Concept2 token save, sync, and disconnect actions backed by `Concept2SyncController`.
15. **Keychain only**: The Settings token flow must persist tokens only through `TokenStore`; production uses `KeychainTokenStore`.
16. **Persistent cache**: Production sync uses `SQLiteWorkoutCache` under Application Support, not an in-memory or mock cache.
17. **State tracking**: App sync uses `SyncStateTracker` to report in-progress, success, failure, and cached workout count.
18. **Material UX**: A successful sync replaces demo data with cached Concept2 workouts and disables demo mode so the main library reflects real user data.
19. **Disconnect**: Disconnect deletes the token, clears the local workout cache, and clears the in-memory library.

## Non-Goals (this PR)

- No background sync scheduling.
- No real network calls in tests.
- No Bluetooth or hardware work.
- No new storage schema (uses existing `WorkoutCache` protocol).
- No PB detection or analytics enrichment during sync.

## Privacy Invariant

`WorkoutSyncError` descriptions must not include:
- BYOT tokens.
- Authorization header values.
- Full raw workout payloads.
- User identifiers.

Sufficient context for debugging (e.g., workout ID) is acceptable.
