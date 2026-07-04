# Phase 5 Design: Compare, Export, Share, and Annotations Foundation

## Architecture

All new domain logic lives in `RowPlayCore` under new subdirectories:
- `Sources/RowPlayCore/Compare/` — workout comparison and rep detection
- `Sources/RowPlayCore/Export/` — CSV/JSON export formatting
- `Sources/RowPlayCore/Import/` — HR import and merge
- `Sources/RowPlayCore/Annotations/` — annotation model and store
- `Sources/RowPlayCore/Share/` — local share package format

## Comparison

`WorkoutComparison` is a stateless enum (namespace) with static methods, matching the pattern used by `WorkoutAnalytics`. It depends on existing `WorkoutAnalytics.distanceBand`/`durationBand` and `ComparabilityGuard`. Fixed-distance pieces in the same distance band compare by elapsed time; fixed-time/JustRow pieces compare by average pace so equal-duration rows do not tie just because their elapsed time matches.

Side stats prefer stroke-derived values, but pace consistency falls back to non-rest split paces when a detail has no stroke stream. Power fallbacks guard non-positive pace and use sport-aware watts conversion.

The distance overlay resamples strokes onto a shared metre grid using linear interpolation — the same algorithm as the web's `sampleStrokeAtDistance`.

`RepDetection` is gated by `Workout.isInterval` before split rows are treated as reps. Split-summary fallback series use sport-aware watts conversion, while stroke-backed series keep the logged watts.

## Export

`WorkoutExport` produces CSV and JSON from `[Workout]`. The CSV column order matches the web export exactly for round-trip compatibility. Workout dates are emitted as Concept2 logbook timestamp strings (`YYYY-MM-DD HH:MM:SS`) in UTC, matching the web export and native `RowPlayDateTime` parser. CSV escaping follows RFC 4180 with formula-injection protection.

## HR Import

`HrImport` ports the pure interpolation and merge logic from `src/lib/hrImport.ts`. The actual file parsing (FIT/TCX/GPX) is out of scope — this PR provides the merge engine only. If an import has no usable samples or an offset maps all samples outside the workout, the prior workout-level average HR is preserved.

## Annotations

`AnnotationStore` protocol mirrors the web's D1-backed annotation API but uses the Phase 4 `WorkoutCache`-style async protocol pattern. `InMemoryAnnotationStore` is the test/demo implementation and removes empty workout buckets after the last annotation is deleted.

## Share Package

`SharePackage` is a Codable struct that captures a `WorkoutDetail` plus export metadata. `SharePackageBuilder` applies the same redaction as the web's `redactForPublic` — stripping serialNumber, device, deviceOs, deviceOsVersion from metadata.

## Naming Conventions

- Swift `camelCase` for all properties (already established).
- `Stroke.cadence` maps to web's `spm` (already established in Phase 0).
- `Stroke.heartRate` maps to web's `hr` (already established).
- `Workout` model uses `Date` for `date` (already established).
