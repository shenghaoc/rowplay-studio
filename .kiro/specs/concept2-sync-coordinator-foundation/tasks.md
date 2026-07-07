# Concept2 Sync Coordinator Foundation — Tasks

## Implementation

- [ ] Create `Sources/RowPlayCore/Sync/WorkoutSyncResult.swift` — result value type with counts and timestamps
- [ ] Create `Sources/RowPlayCore/Sync/WorkoutSyncError.swift` — typed errors with privacy-safe descriptions
- [ ] Create `Sources/RowPlayCore/Sync/WorkoutSyncState.swift` — lightweight sync state enum
- [ ] Create `Sources/RowPlayCore/Sync/WorkoutSyncCoordinator.swift` — sync orchestration bridging client to cache

## Tests

- [ ] Create `Tests/RowPlayCoreTests/Sync/WorkoutSyncCoordinatorTests.swift`
  - [ ] testSyncAllFetchesAndSavesWorkoutDetails — fake client returns two workouts, coordinator saves both, result savedCount is 2, cache contains both details
  - [ ] testSyncAllReturnsCounts — fake client returns known number of workouts, assert fetchedCount and savedCount
  - [ ] testSyncAllDoesNotUseRealNetwork — fake client records calls, no URLSession or real URL used
  - [ ] testClientFailureThrowsSyncError — fake client throws, coordinator throws WorkoutSyncError.clientFailed
  - [ ] testCacheFailureThrowsSyncError — fake cache throws on save, coordinator throws WorkoutSyncError.cacheFailed or increments failedCount
  - [ ] testMappingFailureThrowsSyncError — assert mapping error for malformed response
  - [ ] testSyncIsIdempotentForSameWorkoutIDs — run sync twice, cache count remains stable
  - [ ] testErrorsDoNotExposeToken — force failure, assert error description does not contain fake token

## Docs

- [ ] Update `docs/source-map.md`
- [ ] Update `docs/beta-readiness.md`
- [ ] Update `docs/roadmap.md` if needed

## Validation

- [ ] `swift test` passes
- [ ] `swift build` passes
- [ ] `git diff --check` clean
- [ ] No UI, Bluetooth, real network, or token changes
