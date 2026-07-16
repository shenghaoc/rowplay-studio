# Phase 10B - Complete Rival Workflow — Design

## Overview

Phase 10B extends Phase 10A’s past-session ghost into a complete local rival workflow. All pure math and parsing live in `RowPlayCore`. macOS UI, file panels, ImageRenderer PNG, and share sheet live in `RowPlayStudio`. `WorkoutLibrary` past-session ranking remains unchanged.

## Core Models

### ReplayRival
Portable value type with stable `id`, `kind` (session / constantPace / importedFile), `displayLabel`, `strokes`, `hasGenuineStrokeData`, optional `sessionWorkoutID`, optional `targetPace`, optional `localFileName` (UI-only).

### ReplayRivalFactory
- Session: from `WorkoutDetail` (≥2 strokes).
- Constant pace: two-point trace; distance axis ends at player distance; time axis ends at player duration with derived distance; sport-aware watts; exact finite-`Double` identity keys prevent cache collisions between nearby valid inputs.
- Imported: from normalized strokes; non-genuine; deterministic identity fingerprints both last-path-component and normalized trace so same-named replacement files invalidate cached UI/3D state.

### ReplayRivalFileParser
Dependency-free CSV/TCX/FIT parser with size and sample caps. CSV uses a streaming quote-aware state machine with quoted-newline support and malformed-quote rejection. TCX uses Foundation XMLParser for namespace-insensitive extraction, rejects DTD/entity declarations across supported XML encodings, and strictly rejects malformed documents. FIT is a bounded record-message decoder, including compressed timestamps, with declared-payload, definition-architecture, field, and buffer bounds checks. Normalization keeps the farthest sample at an equal timestamp so emitted time is strictly increasing. Returns strokes + last path component or typed error.

### ReplayRaceResult
`ReplayRaceResultCalculator` produces optional completed results:
- Distance: first interpolated time each trace crosses target distance.
- Time: distance at target duration.
- Outcomes playerWon / rivalWon / tie with finite non-negative margins.

### ReplayRaceReport
Versioned Codable schema excluding tokens, comments, paths, filenames, internal workout/session IDs, hardware IDs, account IDs, logs, and public URLs. Builder maps imported rivals to the generic label “Imported rival”; session cards use a date rather than an identifier. `RivalSummary` includes sanitized result distance, elapsed time, and average pace. These metrics are additive optional version-1 fields: legacy version-1 reports decode them as `nil`, so the schema version remains 1 rather than introducing a needless breaking version.

## UI Design

### ReplayView
- `activeRival: ReplayRival?` replaces session-only `selectedGhostID`.
- Menu adds constant-pace and import actions; pace popover; balanced security-scope acquisition and release contained with bounded file reading and parsing in one detached import operation.
- A monotonic import generation token discards stale detached completions after a newer rival selection; task cancellation is propagated to the detached worker and checked during bounded reads plus the CSV, TCX, FIT, and normalization loops.
- `cachedRaceResult` recomputed only on rival (or detail) change.
- Finish banner when `state.time >= duration - 0.05` with export/share actions.
- Seeking before finish hides the banner without clearing the cache.

### RealityReplaySceneView
- Input: `rival: ReplayRival?` instead of `WorkoutDetail?`.
- Genuine stroke data → pose context + `computeAtTime`.
- Non-genuine → `ReplayStrokePose.fallback` from distance phase.
- `Replay3DSceneIdentity.rivalID: String?`.
- Rival and quality identity rebuild only the inner RealityKit graph. Camera/orbit and adaptive-quality controllers remain owned by a workout/sport-keyed outer view so rival changes preserve those settings without carrying cached live aggregates into another workout.

### Race Card
- `ReplayRaceCardView` + `ReplayRaceCardRenderer` (ImageRenderer → PNG).
- Session, pace-boat, and imported cards render the report's privacy-safe rival result metrics; imported cards never substitute the local filename for those metrics.
- Compact fixed-canvas spacing keeps metric-rich cards unclipped; the explicit accessibility summary converts the visual separator to spoken punctuation.
- `ReplayRaceReportTransferItem` / `ReplayRaceCardTransferItem` for exporters and ShareLink.
- Generic suggested export filenames contain no internal workout/session identifier.
- Share-card data is pre-rendered when the finish verdict appears, making the native share sheet a single-click action; rival and appearance changes invalidate and regenerate it.

## Privacy

- No new logs by default; if added, use `PrivacySafeLogger` + redaction.
- Never log filenames, paths, contents, strokes, or report JSON bodies.
- Export JSON omits `localFileName` and internal workout/session IDs and uses generic rival labels for imported files.

## Performance

- File read and parse off main actor; read stops at 25 MiB + 1 byte and parsing enforces the 25 MiB / 200k sample caps.
- Race calculation O(N) once per rival selection.
- Past-session display/accessibility lookups use an initializer-built ID map rather than render-time array scans.
- 2D paths are precomputed by `ReplayRivalPathBuilder`; shorter rivals hold at the player finish, longer rivals interpolate at that cutoff, and dense visual traces are capped at 2,048 points while full traces remain available to race math.
- 3D pose contexts rebuilt only on rival identity change.

## Testing Strategy

- Golden fixtures for sources and race results.
- Core unit tests for factory/parser/result/report.
- Studio tests for workflow construction, path generation, PNG signature, JSON privacy, scene identity.
- 3D coverage: session genuine pose path, constant-pace/imported fallback, rival change clearing aggregates.
