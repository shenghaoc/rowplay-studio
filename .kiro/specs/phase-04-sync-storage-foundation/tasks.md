# Phase 04 Concept2 Sync, Privacy, and Local Storage Foundation Tasks

- [x] Create `TokenStore.swift` with `TokenStore` protocol, `KeychainTokenStore`, and `FakeTokenStore`.
- [x] Create `Concept2Client.swift` with `Concept2APIClient` protocol, `Concept2Page`, and `MockConcept2Client`.
- [x] Create `WorkoutCache.swift` with `WorkoutCache` protocol and `InMemoryWorkoutCache`.
- [x] Create `PrivacySafeLogger.swift` with `redact()` and `PrivacySafeLogger`.
- [x] Create `SyncStateTracker.swift` with `SyncState` and `SyncStateTracker`.
- [x] Create `TokenStoreTests.swift` covering save/load/delete round-trip through `FakeTokenStore`.
- [x] Create `Concept2ClientTests.swift` covering mock client fixture data and pagination.
- [x] Create `WorkoutCacheTests.swift` covering save, load, delete, and idempotent operations.
- [x] Create `PrivacySafeLoggerTests.swift` covering redaction patterns and idempotency.
- [x] Create `SyncStateTrackerTests.swift` covering state transitions.
- [x] Create `.kiro/specs/phase-04-sync-storage-foundation` spec documents.
- [x] Update `docs/source-map.md` with Phase 4 mappings.
- [x] Update `docs/roadmap.md` Phase 4 status.
- [x] Run `swift test` — all tests pass (260 tests, 0 failures).
- [x] Run `swift build` — clean build.
- [x] Run `git diff --check` — no whitespace errors.
