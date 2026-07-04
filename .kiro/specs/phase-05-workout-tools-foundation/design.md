# Phase 5 Design: Compare, Export, Share, and Annotations Foundation

## Architecture

All new domain logic lives in `RowPlayCore` under new subdirectories:
- `Sources/RowPlayCore/Compare/` — workout comparison and rep detection
- `Sources/RowPlayCore/Export/` — CSV/JSON export formatting
- `Sources/RowPlayCore/Import/` — HR import and merge
- `Sources/RowPlayCore/Annotations/` — annotation model and store
- `Sources/RowPlayCore/Share/` — local share package format

## Comparison

`WorkoutComparison` is a stateless enum (namespace) with static methods, matching the pattern used by `WorkoutAnalytics`. It depends on existing `WorkoutAnalytics.distanceBand`/`durationBand` and `ComparabilityGuard`.

The distance overlay resamples strokes onto a shared metre grid using linear interpolation — the same algorithm as the web's `sampleStrokeAtDistance`.

## Export

`WorkoutExport` produces CSV and JSON from `[Workout]`. The CSV column order matches the web export exactly for round-trip compatibility. CSV escaping follows RFC 4180 with formula-injection protection.

## HR Import

`HrImport` ports the pure interpolation and merge logic from `src/lib/hrImport.ts`. The actual file parsing (FIT/TCX/GPX) is out of scope — this PR provides the merge engine only.

## Annotations

`AnnotationStore` protocol mirrors the web's D1-backed annotation API but uses the Phase 4 `WorkoutCache`-style async protocol pattern. `InMemoryAnnotationStore` is the test/demo implementation.

## Share Package

`SharePackage` is a Codable struct that captures a `WorkoutDetail` plus export metadata. `SharePackageBuilder` applies the same redaction as the web's `redactForPublic` — stripping serialNumber, device, deviceOs, deviceOsVersion from metadata.

## Naming Conventions

- Swift `camelCase` for all properties (already established).
- `Stroke.cadence` maps to web's `spm` (already established in Phase 0).
- `Stroke.heartRate` maps to web's `hr` (already established).
- `Workout` model uses `Date` for `date` (already established).
