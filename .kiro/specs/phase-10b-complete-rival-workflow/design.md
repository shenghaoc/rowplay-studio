# Phase 10B - Complete Rival Workflow — Design

## Overview

Phase 10B extends Phase 10A’s past-session ghost into a complete local rival workflow. All pure math and parsing live in `RowPlayCore`. macOS UI, file panels, ImageRenderer PNG, and share sheet live in `RowPlayStudio`. `WorkoutLibrary` past-session ranking remains unchanged.

## Core Models

### ReplayRival
Portable value type with stable `id`, `kind` (session / constantPace / importedFile), `displayLabel`, `strokes`, `hasGenuineStrokeData`, optional `sessionWorkoutID`, optional `targetPace`, optional `localFileName` (UI-only).

### ReplayRivalFactory
- Session: from `WorkoutDetail` (≥2 strokes).
- Constant pace: two-point trace; distance axis ends at player distance; time axis ends at player duration with derived distance; sport-aware watts.
- Imported: from normalized strokes; non-genuine.

### ReplayRivalFileParser
Dependency-free CSV/TCX/FIT parser with size and sample caps. CSV uses a quote-aware state machine. FIT is a bounded record-message decoder, including compressed timestamps, with explicit buffer bounds checks. Returns strokes + last path component or typed error.

### ReplayRaceResult
`ReplayRaceResultCalculator` produces optional completed results:
- Distance: first interpolated time each trace crosses target distance.
- Time: distance at target duration.
- Outcomes playerWon / rivalWon / tie with finite non-negative margins.

### ReplayRaceReport
Versioned Codable schema excluding tokens, comments, paths, filenames, hardware IDs, account IDs, logs, and public URLs. Builder maps imported rivals to the generic label “Imported rival”.

## UI Design

### ReplayView
- `activeRival: ReplayRival?` replaces session-only `selectedGhostID`.
- Menu adds constant-pace and import actions; pace popover; balanced main-actor security-scope lifetime around detached file reading and parsing.
- `cachedRaceResult` recomputed only on rival (or detail) change.
- Finish banner when `state.time >= duration - 0.05` with export/share actions.
- Seeking before finish hides the banner without clearing the cache.

### RealityReplaySceneView
- Input: `rival: ReplayRival?` instead of `WorkoutDetail?`.
- Genuine stroke data → pose context + `computeAtTime`.
- Non-genuine → `ReplayStrokePose.fallback` from distance phase.
- `Replay3DSceneIdentity.rivalID: String?`.

### Race Card
- `ReplayRaceCardView` + `ReplayRaceCardRenderer` (ImageRenderer → PNG).
- `ReplayRaceReportTransferItem` / `ReplayRaceCardTransferItem` for exporters and ShareLink.
- Share-card data is pre-rendered when the finish verdict appears, making the native share sheet a single-click action.

## Privacy

- No new logs by default; if added, use `PrivacySafeLogger` + redaction.
- Never log filenames, paths, contents, strokes, or report JSON bodies.
- Export JSON omits `localFileName` and uses generic rival labels for imported files.

## Performance

- File parse off main actor; 25 MiB / 200k sample caps.
- Race calculation O(N) once per rival selection.
- 2D paths precomputed; Canvas only strokes cached paths.
- 3D pose contexts rebuilt only on rival identity change.

## Testing Strategy

- Golden fixtures for sources and race results.
- Core unit tests for factory/parser/result/report.
- Studio tests for workflow construction, path generation, PNG signature, JSON privacy, scene identity.
- 3D coverage: session genuine pose path, constant-pace/imported fallback, rival change clearing aggregates.
