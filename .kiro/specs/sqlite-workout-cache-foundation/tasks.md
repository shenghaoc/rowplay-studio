# SQLite Workout Cache Foundation — Tasks

## T1: Extend WorkoutCache protocol

- Add `migrate()`, `save(detail:)`, `save(details:)`, `listWorkouts()`, `detail(id:)`, `delete(id:)`, and `deleteAll()` support to the async `WorkoutCache` protocol surface.
- Preserve legacy Phase 4 aliases for existing callers.
- Add implementations to `InMemoryWorkoutCache`.
- Existing tests continue to pass.

## T2: Add Package.swift linker setting

- Add `linkerSettings: [.linkedLibrary("sqlite3")]` to RowPlayCore target.
- No third-party dependencies added.

## T3: Create WorkoutCacheError

- New file: `Sources/RowPlayCore/Storage/WorkoutCacheError.swift`
- Error enum with cases: openFailed, migrationFailed, queryFailed, encodingFailed, decodingFailed.
- Equatable conformance.

## T4: Create SQLiteWorkoutCacheMigration

- New file: `Sources/RowPlayCore/Storage/SQLiteWorkoutCacheMigration.swift`
- `Migration` struct with `static func run(db:)` that creates the workouts table and sets user_version = 1.
- Idempotent: safe to call multiple times.

## T5: Create SQLiteWorkoutCache

- New file: `Sources/RowPlayCore/Storage/SQLiteWorkoutCache.swift`
- Conforms to `WorkoutCache` protocol.
- Uses system SQLite3 C API.
- Serial DispatchQueue for thread safety.
- JSON encoding/decoding for WorkoutDetail storage.

## T6: Create SQLiteWorkoutCacheTests

- New file: `Tests/RowPlayCoreTests/Storage/SQLiteWorkoutCacheTests.swift`
- 8 required test methods covering migration, round-trip, delete, persistence.

## T7: Update documentation

- `docs/source-map.md` — add SQLiteWorkoutCache entry.
- `docs/beta-readiness.md` — update storage gap status.
- `docs/roadmap.md` — update Phase 4 status if needed.

## T8: Validate

- `swift test` passes.
- `swift build` passes.
- `git diff --check` passes.
