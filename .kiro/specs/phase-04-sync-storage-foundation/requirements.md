# Phase 4 Requirements: Concept2 Sync, Privacy, and Local Storage Foundation

## R1: Token Store Abstraction

The native app must provide a secure, injectable token store for Concept2 BYOT (bring-your-own-token) credentials.

- **R1.1** `TokenStore` protocol defines `saveToken(_:)`, `loadToken()`, and `deleteToken()` operations.
- **R1.2** `KeychainTokenStore` implements `TokenStore` using the macOS Security framework (Keychain Services).
- **R1.3** Tokens are stored under a well-known service name (`com.rowplay-studio.concept2-token`) with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility.
- **R1.4** The Keychain item uses the `kSecClassGenericPassword` class with a stable account key.
- **R1.5** A `FakeTokenStore` in-memory implementation is provided for tests and previews.
- **R1.6** Tokens must never be written to UserDefaults, plain files, logs, fixtures, or test assertions (only the fake store holds them in memory for test control flow).

## R2: Concept2 API Client Boundary

The native app must define an injectable boundary for Concept2 API calls.

- **R2.1** `Concept2APIClient` protocol defines `fetchWorkouts(page:perPage:)` returning `[Workout]` plus pagination metadata.
- **R2.2** The protocol also defines `fetchWorkoutDetail(id:)` returning `WorkoutDetail`.
- **R2.3** A `MockConcept2Client` implementation returns deterministic fixture data for tests.
- **R2.4** The real URLSession-based implementation is deferred to a follow-up PR; this PR establishes the protocol boundary only.
- **R2.5** The client is generic over token supply — it accepts a `() async throws -> String` closure or equivalent for the access token, decoupling it from any specific token store.

## R3: Workout Cache Abstraction

The native app must provide a local workout cache for offline-first access.

- **R3.1** `WorkoutCache` protocol defines async `saveWorkouts(_:)`, `saveDetail(_:)`, `loadAllWorkouts()`, `loadWorkout(id:)`, and `deleteAll()` operations.
- **R3.2** `InMemoryWorkoutCache` provides a simple in-memory implementation suitable for demo data and early integration.
- **R3.3** The cache stores `Workout` and `WorkoutDetail` models as-is (no schema translation needed at this stage).
- **R3.4** `deleteAll()` clears the entire cache — used for disconnect/logout flows.
- **R3.5** The cache protocol intentionally does not prescribe a storage backend; a future SQLite implementation can conform without changing callers.
- **R3.6** Cache methods are async so persistent backends can avoid blocking the main actor.

## R4: Privacy-Safe Logging

The native app must redact sensitive data before logging.

- **R4.1** `PrivacySafeLogger` wraps `os.Logger` and redacts strings before emitting.
- **R4.2** Redaction rules define known sensitive patterns: hex tokens (32+ chars), Bearer headers, cookie headers, JSON `token` / `access_token` values, generic `token=...` patterns, and raw JSON object or array blobs > 100 characters.
- **R4.3** `redact(_:)` is a pure function that applies all patterns and returns a sanitized string.
- **R4.4** `PrivacySafeLogger.error(_:)` and `.warn(_:)` apply redaction to the main message and all string arguments.
- **R4.5** Error messages are redacted before they are emitted to the system log, including errors interpolated into the main message string.
- **R4.6** The redaction function is idempotent — calling it on already-redacted text is safe.

## R5: Sync State Model

The native app must track sync progress without importing Cloudflare D1 assumptions.

- **R5.1** `SyncState` struct records `lastSyncDate`, `totalWorkouts`, `inProgress`, `lastError`, and `lastErrorDate`.
- **R5.2** `SyncStateTracker` is an `@Observable`, `@MainActor` class (macOS 14+) that publishes sync state changes on the main actor.
- **R5.3** The tracker is backed by the workout cache (count-based) and a simple in-memory error log.
- **R5.4** The tracker does not depend on any specific storage backend; it reads from the cache protocol.

## R6: Test Coverage

- **R6.1** `KeychainTokenStoreTests` verify save/load/delete round-trip through `FakeTokenStore` (real Keychain tests require signing and are out of scope for CI).
- **R6.2** `MockConcept2ClientTests` verify fixture data is returned correctly and pagination works.
- **R6.3** `WorkoutCacheTests` verify async save, load, delete, and idempotent operations through `InMemoryWorkoutCache`.
- **R6.4** `PrivacySafeLoggerTests` verify redaction of hex tokens, Bearer headers, cookie headers, query credentials, JSON token values, JSON object and array blobs, and idempotency.
- **R6.5** `SyncStateTrackerTests` verify state transitions: idle → syncing → complete/error.
- **R6.6** `swift test` passes.
- **R6.7** `swift build` passes.

## R7: Non-Goals

- No real URLSession-based Concept2 sync (follow-up PR).
- No SQLite or Core Data migration tests (follow-up PR).
- No replay rendering, sharing/export, live mode, or Bluetooth work.
- No Cloudflare KV/D1 assumptions ported into native core.
- No OAuth flow (BYOT only in this PR).
