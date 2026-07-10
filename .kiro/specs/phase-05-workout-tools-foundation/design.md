# Phase 5 Design: Compare, Export, Share, and Annotations Foundation

## Architecture

All new domain logic lives in `RowPlayCore` under new subdirectories:
- `Sources/RowPlayCore/Compare/` — workout comparison and rep detection
- `Sources/RowPlayCore/Export/` — CSV/JSON export formatting
- `Sources/RowPlayCore/Import/` — HR import and merge
- `Sources/RowPlayCore/Annotations/` — annotation model and store
- `Sources/RowPlayCore/Share/` — local share package format

Native workflow wiring lives in `RowPlayStudio/Views` as small feature views:
- `WorkoutToolsView` composes the Phase 5 tools on the workout detail surface.
- `WorkoutFileActionsView` owns CSV/JSON/local-share file actions.
- `HrImportPanelView` owns offline HR sample import and applies updates through `WorkoutLibrary`.
- `WorkoutComparisonPanel` owns compare selection, verdict/stats/interval rows, and pace overlay rendering.
- `AnnotationPanelView` owns local add/delete annotation UI.

`WorkoutDetailView` remains a composition surface. `WorkoutLibrary` owns selected-workout mutation, compare candidate selection, and the local annotation store instance so derived dashboard/sidebar data stays coherent after HR import.

## Comparison

`WorkoutComparison` is a stateless enum (namespace) with static methods, matching the pattern used by `WorkoutAnalytics`. It depends on existing `WorkoutAnalytics.distanceBand`/`durationBand` and `ComparabilityGuard`. Fixed-distance pieces in the same distance band compare by elapsed time; fixed-time/JustRow pieces compare by average pace so equal-duration rows do not tie just because their elapsed time matches. Comparison is a native-only capability because rowplay PR #166 retired the web compare page.

Side stats prefer stroke-derived values, but pace consistency falls back to non-rest split paces when a detail has no stroke stream. Power fallbacks guard non-positive pace and use sport-aware watts conversion.

The distance overlay resamples strokes onto a shared metre grid using linear interpolation — the same algorithm as the web's `sampleStrokeAtDistance`.

`RepDetection` is gated by `Workout.isInterval` before split rows are treated as reps. Split-summary fallback series use sport-aware watts conversion, while stroke-backed series keep the logged watts.

## Export

`WorkoutExport` produces CSV and JSON from `[Workout]`. The CSV column order matches the web export exactly for round-trip compatibility. Workout dates are emitted as Concept2 logbook timestamp strings (`YYYY-MM-DD HH:MM:SS`) in UTC, matching the web export and native `RowPlayDateTime` parser. CSV escaping follows RFC 4180 with formula-injection protection.

## HR Import

`HrImport` ports the pure interpolation and merge logic from `src/lib/hrImport.ts`. The actual file parsing (FIT/TCX/GPX) is out of scope — this PR provides the merge engine only. If an import has no usable samples or an offset maps all samples outside the workout, the prior workout-level average HR is preserved.

The native detail surface includes an offline sample-series import action using `NSOpenPanel`. It accepts JSON arrays of `{ "t": seconds, "hr": bpm }` or simple two-column CSV rows, then applies `HrImport.applyHrImport` to the selected workout through `WorkoutLibrary.updateDetail`. This keeps HR import usable without expanding into full FIT/TCX/GPX parsing in this PR.

## Annotations

`AnnotationStore` is a native-only async protocol following the Phase 4
`WorkoutCache`-style pattern. The web's D1-backed annotation API was retired
in rowplay PR #166. `InMemoryAnnotationStore` is the test/demo implementation
and removes empty workout buckets after the last annotation is deleted.

## Share Package

`SharePackage` is a Codable struct that captures a `WorkoutDetail` plus export
metadata. `SharePackageBuilder` enforces the native privacy invariant by
stripping serialNumber, device, deviceOs, and deviceOsVersion from metadata.

The native share action saves this local package through `NSSavePanel`. It does not call a companion web service, mint a public URL, or add any public-sharing surface.

## Native UX and HIG

The detail tools use standard macOS controls: buttons with SF Symbols, a menu picker for compare targets, sliders/steppers for timestamp and HR offset values, and system save/open panels for file access. Destructive annotation delete actions use a trash icon and destructive role. No custom chrome, nonstandard controls, or hidden public-sharing side effects are introduced.

The UI modules are intentionally split by workflow so the main detail view does not become a god module.

## Naming Conventions

- Swift `camelCase` for all properties (already established).
- `Stroke.cadence` maps to web's `spm` (already established in Phase 0).
- `Stroke.heartRate` maps to web's `hr` (already established).
- `Workout` model uses `Date` for `date` (already established).
