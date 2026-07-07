# Concept2 Sync Coordinator Foundation — Tasks

## Implementation

- [x] Create `Sources/RowPlayCore/Sync/WorkoutSyncResult.swift` — result value type with counts and timestamps
- [x] Create `Sources/RowPlayCore/Sync/WorkoutSyncError.swift` — typed errors with privacy-safe descriptions
- [x] Create `Sources/RowPlayCore/Sync/WorkoutSyncCoordinator.swift` — sync orchestration bridging client to cache
- [x] Create `Sources/RowPlayStudio/Stores/Concept2SyncController.swift` — app-shell sync store using TokenStore, SQLiteWorkoutCache, URLSessionConcept2Client, and SyncStateTracker
- [x] Wire Concept2 token save, sync, and disconnect actions into `SettingsView`
- [x] Wire `Workout > Sync Concept2 Logbook` menu command
- [x] Add `WorkoutLibrary.replaceWithSyncedDetails(_:)` so successful sync loads real cached workouts and disables demo mode

## Tests

- [x] Create `Tests/RowPlayCoreTests/Sync/WorkoutSyncCoordinatorTests.swift`
  - [x] testSyncAllFetchesAndSavesWorkoutDetails — fake client returns two workouts, coordinator saves both, result savedCount is 2, cache contains both details
  - [x] testSyncAllReturnsCounts — fake client returns known number of workouts, assert fetchedCount and savedCount
  - [x] testSyncAllDoesNotUseRealNetwork — fake client records calls, no URLSession or real URL used
  - [x] testClientFailureThrowsSyncError — fake client throws, coordinator throws WorkoutSyncError.clientFailed
  - [x] testCacheFailureIncrementsFailedCount — fake cache throws on per-workout save, coordinator increments failedCount
  - [x] testDetailFetchFailureIncrementsFailedCount — per-workout decoding failure increments failedCount
  - [x] testSyncIsIdempotentForSameWorkoutIDs — run sync twice, cache count remains stable
  - [x] testErrorsDoNotExposeToken — force failure, assert error description does not contain fake token
  - [x] testCancellationPropagatesFromDetailFetch — detail cancellation is re-thrown
  - [x] testCancellationPropagatesFromCacheSave — cache-save cancellation is re-thrown
  - [x] testHTTP401ViaClientErrorAbortsSync — `Concept2ClientError.httpError(401)` aborts early
  - [x] testSyncErrorDescriptionRedactsDetails — public error descriptions redact associated strings
  - [x] testMigrateCalledBeforeSync — cache migration runs before summary fetch
- [x] Create `Tests/RowPlayStudioTests/Concept2SyncControllerTests.swift`
  - [x] token save uses `TokenStore` and marks the app connected
  - [x] sync loads cached details into `WorkoutLibrary` and disables demo mode
  - [x] sync without a token does not create a client
  - [x] disconnect deletes token, cache, and in-memory library state

## Docs

- [x] Update `docs/source-map.md`
- [x] Update `docs/beta-readiness.md`
- [x] Update `docs/roadmap.md`

## Validation

- [x] `swift test` passes
- [x] `swift build` passes
- [x] `git diff --check` clean
- [x] `./script/build_and_run.sh --verify` launches the staged app bundle
- [x] No Bluetooth changes
- [x] No real network calls in tests
