# Phase 5 Requirements: Compare, Export, Share, and Annotations Foundation

## R1: Workout Comparison

The native app must compare two workouts side-by-side as a native-only
capability. The web compare page was retired in rowplay PR #166, so comparison
is not a current web-parity target.

- **R1.1** `CompareVerdict` struct records `winner` (a/b/tie), `timeDeltaSec`, and `paceDelta`.
- **R1.2** `WorkoutComparison.compareVerdict(_:_:)` decides which workout was "better" for like-for-like fixed-distance pieces (same distance band) by time, and uses average pace for fixed-time/JustRow pieces or other non-distance-race comparisons.
- **R1.3** `WorkoutSideStats` struct records time, pace, avgWatts, best5sPower, avgHr, peakHr, avgDps, and paceConsistency.
- **R1.4** `WorkoutComparison.sideStats(_:)` computes per-workout statistics from strokes and splits, including split-pace fallback for pace consistency when stroke data is unavailable.
- **R1.5** `IntervalCompareRow` records per-rep pace, time, and deltas when both workouts have interval splits.
- **R1.6** `WorkoutComparison.compareIntervalReps(_:_:)` returns per-rep deltas, or nil when workouts are not both interval pieces.
- **R1.7** `DistanceOverlay` records resampled pace/power/HR arrays on a shared distance grid.
- **R1.8** `WorkoutComparison.buildDistanceOverlay(_:_:steps:)` resamples two stroke streams onto a shared distance grid for chart overlay.
- **R1.9** The native workout detail surface exposes a comparison panel with candidate selection, verdict, side stats, interval rows, and a pace overlay when stroke data is available.

## R2: Rep Detection

The native app must detect multi-rep interval workouts and provide per-rep series for comparison charts.

- **R2.1** `RepSeries` struct records repIndex, avgPace, and arrays for times, pace, rate, power, and hr.
- **R2.2** `RepDetection.detectReps(_:)` returns one `RepSeries` per work interval, or nil when the workout is not marked as an interval workout or is not a recognisable multi-rep piece (< 2 work intervals or each < 30 s).
- **R2.3** `RepDetection.repAvgPace(_:)` returns the average pace for a rep series.
- **R2.4** `RepDetection.repsHaveHr(_:)` returns true when any rep carries HR data.
- **R2.5** Split-summary fallback power uses sport-aware pace-to-watts conversion so BikeErg reps do not use RowErg watts.

## R3: Export Formatting

The native app must export workout data as CSV and JSON with parity to the web export.

- **R3.1** `WorkoutExport.csv(_:)` produces RFC 4180-compliant CSV with the same column order as the web export and Concept2 logbook date strings (`YYYY-MM-DD HH:MM:SS`).
- **R3.2** `WorkoutExport.json(_:)` produces a JSON export with schema metadata (`rowplay-logbook-export`, version 1) and workout dates encoded as Concept2 logbook date strings.
- **R3.3** CSV cell escaping handles commas, quotes, newlines, and formula-triggering characters (`=`, `+`, `-`, `@`, tab).
- **R3.4** `WorkoutExport.exportFilename(ext:)` and `workoutExportFilename(id:ext:)` generate stable filenames.
- **R3.5** TCX export is deferred to a follow-up PR to keep this PR narrow.
- **R3.6** The native workout detail surface exposes CSV and JSON export actions through the standard macOS save panel.

## R4: Heart Rate Import

The native app must support importing external HR data and merging it into workout strokes.

- **R4.1** `HrSample` struct records `t` (elapsed seconds) and `hr` (bpm).
- **R4.2** `HrImport.extractHrSeries(_:)` extracts valid HR samples from strokes.
- **R4.3** `HrImport.interpolateHr(_:at:)` performs linear interpolation of HR at a given time.
- **R4.4** `HrImport.mergeHrIntoStrokes(_:samples:offsetSec:)` merges external HR samples into workout strokes.
- **R4.5** `HrImport.summarizeHr(_:)` computes avg/min/max HR from strokes.
- **R4.6** `HrImport.applyHrImport(_:samples:offsetSec:)` produces a new `WorkoutDetail` with merged HR across strokes and splits, preserving the existing workout average when an import produces no usable merged HR.
- **R4.7** `HrImport.strokesHaveHr(_:)` returns true when any stroke carries HR data.
- **R4.8** The native workout detail surface can import offline HR sample-series files (JSON array or simple CSV `elapsed seconds, bpm`) and apply the merge to the selected workout through `WorkoutLibrary`.

## R5: Annotation Model

The native app must support timestamped coaching annotations on workouts as a
native-only feature. The web annotation API was retired in rowplay PR #166.

- **R5.1** `Annotation` struct records `id`, `timestamp` (seconds since workout start), `text`, and `createdAt` (epoch ms).
- **R5.2** `AnnotationStore` protocol defines `loadAnnotations(workoutId:)`, `saveAnnotation(workoutId:_:)`, `deleteAnnotation(workoutId:id:)`, and `deleteAll()` operations.
- **R5.3** `InMemoryAnnotationStore` provides a thread-safe in-memory implementation.
- **R5.4** Annotation text is validated: non-empty, max 1000 characters.
- **R5.5** Annotation timestamp must be non-negative and finite.
- **R5.6** Deleting the last annotation for a workout removes the empty workout bucket from the in-memory store.
- **R5.7** The native workout detail surface exposes add/delete annotation behavior using the async annotation store boundary.

## R6: Local Share Package

The native app must define a local replay package format for sharing without a companion web service.

- **R6.1** `SharePackage` struct captures a workout detail plus metadata needed for offline replay (version, exportedAt, privacy-redacted fields).
- **R6.2** `SharePackageBuilder.build(from:)` creates a `SharePackage` from a `WorkoutDetail`, stripping hardware-identifying metadata (serialNumber, device, deviceOs, deviceOsVersion).
- **R6.3** `SharePackage.encode()` produces JSON data suitable for file export.
- **R6.4** `SharePackage.decode(_:)` round-trips from JSON data.
- **R6.5** Public share URL generation and companion web-service integration are out of scope: web public sharing was retired in rowplay PR #166, and this PR defines only the local package format.
- **R6.6** The native workout detail surface exposes a local share package save action and must not create public URLs or include hardware-identifying metadata.

## R7: Native UX, HIG, and Module Boundaries

The native additions must materially improve the workout detail workflow without creating a monolithic view/module.

- **R7.1** Workout tools use standard macOS controls: menus/pickers for compare selection, buttons with SF Symbols for file actions, sliders/steppers for timestamp/offset values, and system save/open panels for file I/O.
- **R7.2** `WorkoutDetailView` remains a composition surface; compare, file actions, HR import, and annotations live in focused app-module views.
- **R7.3** `WorkoutLibrary` owns selected-workout mutation and the local annotation-store instance so derived data stays coherent.
- **R7.4** Share behavior remains local-file based; no public sharing workflow is introduced in this PR.

## R8: Test Coverage

- **R8.1** `WorkoutComparisonTests` cover compareVerdict, sideStats, compareIntervalReps, and buildDistanceOverlay with deterministic fixtures.
- **R8.2** `RepDetectionTests` cover detectReps, repAvgPace, and repsHaveHr.
- **R8.3** `WorkoutExportTests` cover CSV formatting, JSON formatting, CSV escaping, and filename generation.
- **R8.4** `HrImportTests` cover extractHrSeries, interpolateHr, mergeHrIntoStrokes, summarizeHr, applyHrImport, and strokesHaveHr.
- **R8.5** `AnnotationStoreTests` cover save, load, delete, and validation.
- **R8.6** `SharePackageTests` cover encode/decode round-trip and metadata redaction.
- **R8.7** `swift test` passes.
- **R8.8** `swift build` passes.

## R9: Non-Goals

- No Bluetooth/hardware connectivity.
- No live mode.
- No full Concept2 sync expansion.
- No 3D/Metal replay rendering.
- No public sharing that leaks private workout fields.
- No TCX export (deferred to follow-up).
- No companion web share service integration; web public sharing was retired in rowplay PR #166.
