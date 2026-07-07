# Manual Concept2 Sync Wiring — Tasks

## Implementation

- [x] Create `Sources/RowPlayStudio/Stores/Concept2SyncController.swift` — app-shell sync store with token save, sync, and disconnect
- [x] Wire Concept2 token entry, Sync Now, and Disconnect into `SettingsView`
- [x] Wire `Workout > Sync Concept2 Logbook` menu command in `RowPlayStudioApp`
- [x] Add `WorkoutLibrary.replaceWithSyncedDetails(_:)` for cache-backed loading
- [x] Add `WorkoutLibrary.clearData()` for disconnect cleanup

## Tests

- [x] Create `Tests/RowPlayStudioTests/Concept2SyncControllerTests.swift`
  - [x] `testSaveTokenStoresTrimmedTokenAndMarksConnected` — trimmed token saved, isConnected true
  - [x] `testSyncNowLoadsCacheIntoLibraryAndDisablesDemoMode` — sync replaces library, disables demo
  - [x] `testSyncNowWithoutTokenDoesNotCreateClient` — no token → no client, status message
  - [x] `testDisconnectDeletesTokenCacheAndClearsLibrary` — token deleted, cache cleared, library empty
  - [x] `testSyncErrorDoesNotExposeToken` — error messages never contain the raw token

## Docs

- [x] Create `.kiro/specs/manual-concept2-sync-wiring/` spec
- [x] Verify `docs/source-map.md` entries for sync wiring files
- [x] Verify `docs/beta-readiness.md` accurately reflects sync wiring state
- [x] Verify `docs/roadmap.md` Phase 4 status

## Validation

- [x] `swift test` passes (633 tests, 0 failures)
- [x] `swift build` passes
- [x] `git diff --check` clean
- [x] No token in source except harmless fake test strings
- [x] No token persistence outside Keychain
- [x] No background sync
- [x] No Bluetooth changes
