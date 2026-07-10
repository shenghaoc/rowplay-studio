# Persistent Annotation Storage Requirements

## Context

Annotations are a native-only local feature. The web annotation API was retired
by rowplay PR #166. This PR must not recreate server persistence or sync
annotations to any remote service.

The Phase 5 foundation PR added `AnnotationStore` protocol and
`InMemoryAnnotationStore`. That implementation loses all data on app restart.
This PR backs the protocol with a dedicated SQLite database so annotations
survive restarts.

## R1: SQLite Annotation Store

- **R1.1** `SQLiteAnnotationStore` conforms to `AnnotationStore` and lives in
  `Sources/RowPlayCore/Annotations/`, free of SwiftUI and AppKit imports.
- **R1.2** It opens a dedicated Application Support database named
  `annotations.sqlite`. Annotation tables must not be placed in `workouts.sqlite`
  and the workout-cache schema must not change.
- **R1.3** The v1 schema is:

  ```sql
  CREATE TABLE IF NOT EXISTS annotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workout_id INTEGER NOT NULL,
      timestamp REAL NOT NULL,
      text TEXT NOT NULL,
      created_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_annotations_workout_timestamp
      ON annotations (workout_id, timestamp, id);
  ```

- **R1.4** Use `PRAGMA user_version` for migration tracking. Migration is
  atomic and idempotent.
- **R1.5** Use `SQLITE_OPEN_FULLMUTEX`, a private serial `DispatchQueue`,
  prepared statements, bound parameters, `SQLITE_TRANSIENT` for text bindings,
  and `sqlite3_finalize` on every statement.
- **R1.6** The initializer opens and migrates the annotation database
  automatically. This is a deliberate difference from `SQLiteWorkoutCache`
  (which requires an explicit `migrate()` call) so `AnnotationStore` callers
  need no migration method.
- **R1.7** `id == 0` inserts and returns the SQLite-generated ID.
- **R1.8** `text` is trimmed before validation and persistence, and is bound
  and decoded using its exact UTF-8 byte length so valid embedded NUL characters
  round-trip without truncation.
- **R1.9** Updates preserve the original `createdAt`.
- **R1.10** Updating an ID not belonging to that workout throws
  `AnnotationError.notFound`.
- **R1.11** Loads sort by `timestamp` ascending, then `id` ascending.
- **R1.12** Deleting a missing annotation is a no-op.
- **R1.13** `deleteAll` removes every row and resets the AUTOINCREMENT sequence.

## R2: Error Handling

- **R2.1** `AnnotationError` gains persistence-related cases with privacy-safe
  diagnostics.
- **R2.2** Error strings must never include annotation text, tokens, complete
  workout payloads, or SQL containing user content.

## R3: Unavailable Store

- **R3.1** `UnavailableAnnotationStore` throws
  `AnnotationError.storageUnavailable` for every operation.
- **R3.2** It does not silently fall back to in-memory storage in production.

## R4: Factory and App Wiring

- **R4.1** `AnnotationStoreFactory` creates
  `Application Support/RowPlayStudio/annotations.sqlite` and returns
  `SQLiteAnnotationStore`.
- **R4.2** If setup fails, it logs only through `PrivacySafeLogger`/`redact()`
  and returns `UnavailableAnnotationStore`.
- **R4.3** `RowPlayStudioApp` production `WorkoutLibrary` receives
  `AnnotationStoreFactory.makeDefault()`.
- **R4.4** `WorkoutLibrary`'s existing injectable `InMemoryAnnotationStore`
  default is preserved for tests and previews.

## R5: UI Error Display

- **R5.1** `AnnotationPanelView` displays "Annotation storage is unavailable."
  for storage/open/migration/query failures. It never displays raw SQLite
  diagnostics.

## R6: Disconnect Cleanup

- **R6.1** `Concept2SyncController.disconnect(library:)` purges
  `library.annotationStore` as well as the token and workout cache.
- **R6.2** Workout-cache and annotation cleanup failures are tracked
  independently.
- **R6.3** Errors are redacted via `redact()`.
- **R6.4** In-memory workout state is always cleared after token deletion.
- **R6.5** The status message reports
  "Concept2 token deleted; local data cleanup failed." if either purge fails.

## R7: Tests

- **R7.1** `SQLiteAnnotationStoreTests` cover migration/version/index,
  idempotent reopen, insert-generated IDs, persistence after closing/reopening,
  trimming, validation, Unicode and embedded-NUL text round-trips, deterministic
  ordering, update with preserved createdAt, cross-workout update rejection,
  delete, deleteAll with sequence reset, apostrophes/SQL-like text round-trip,
  and concurrent writes without lost rows or duplicate IDs.
- **R7.2** `Concept2SyncControllerTests` prove disconnect purges annotations
  and reports a cleanup failure when annotation deletion throws. Existing
  token/cache/privacy assertions are not weakened.

## R8: Documentation

- **R8.1** `docs/roadmap.md` marks persistent annotation storage complete.
- **R8.2** `docs/source-map.md` adds `SQLiteAnnotationStore` mapping.
- **R8.3** `docs/beta-readiness.md` removes persistent annotation storage from
  beta blockers.
- **R8.4** Phase 5 spec is updated.

## R9: Non-Goals

- No Bluetooth/CoreBluetooth, Cloudflare/D1/KV storage, public sharing, web
  APIs, annotation editing UI, sync annotations to Concept2, TCX/FIT/GPX work,
  OAuth, unrelated refactors, external dependencies, or an Xcode project.
