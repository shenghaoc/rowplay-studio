# Phase 10B - Complete Rival Workflow — Design

## Overview

Phase 10B extends Phase 10A’s past-session ghost into a complete local rival workflow. All pure math and parsing live in `RowPlayCore`. macOS UI, file panels, ImageRenderer PNG, and share sheet live in `RowPlayStudio`. Past-session ranking remains cached in `WorkoutLibrary`; Phase 10B excludes unusable one-stroke traces and adds cached primary replay-content identities so same-ID detail refreshes restart only the affected replay subtree.

## Core Models

### ReplayRival
Portable value type with stable `id`, `kind` (session / constantPace / importedFile), `displayLabel`, `strokes`, `hasGenuineStrokeData`, optional `sessionWorkoutID`, optional `targetPace`, optional `localFileName` (UI-only).

### ReplayRivalFactory
- Session: from `WorkoutDetail` (≥2 strokes); identity fingerprints workout ID plus trace content so a same-ID library refresh invalidates cached replay artifacts.
- Constant pace: two-point trace; distance axis ends at player distance; time axis ends at player duration with derived distance; sport-aware watts; exact finite-`Double` identity keys prevent cache collisions between nearby valid inputs.
- Imported: from normalized strokes; non-genuine; deterministic identity fingerprints both last-path-component and normalized trace so same-named replacement files invalidate cached UI/3D state.

### ReplayRivalFileParser
`ReplayRivalFileParser` is a small public dispatch/normalization facade over focused CSV, TCX, FIT, and shared-support files. The dependency-free parser enforces size and sample caps. CSV uses a streaming Unicode-scalar, quote-aware state machine with quoted-newline support, direct CR/LF/CRLF delimiter handling, and malformed-quote rejection. TCX uses Foundation XMLParser for namespace-insensitive extraction, rejects DTD/entity declarations across supported XML encodings with one full-file code-unit scan, and strictly rejects malformed documents. FIT is a bounded record-message decoder, including compressed timestamps, with declared-payload, definition-architecture, field, and buffer bounds checks. Structurally recognized FIT/TCX content outranks a misleading filename hint. Normalization keeps the farthest sample at an equal timestamp so emitted time is strictly increasing. Returns strokes + last path component or typed error.

### ReplayRaceResult
`ReplayRaceResultCalculator` produces optional completed results:
- Both player and rival traces require at least two strokes before axis-specific math begins.
- Distance: first interpolated time each trace crosses target distance.
- Time: distance at target duration.
- Outcomes playerWon / rivalWon / tie with finite non-negative margins.

### ReplayRaceReport
Versioned Codable schema excluding tokens, comments, paths, filenames, internal workout/session IDs, hardware IDs, account IDs, logs, and public URLs. Builder maps imported rivals to the generic label “Imported rival”; session cards use a date rather than an identifier. Primary metrics describe completion: distance races pair the target distance with the player's interpolated crossing time, while time races pair the distance sampled at the target duration with that duration. Winner-decision shortfall snapshots remain in result margins. `RivalSummary` includes sanitized result distance, elapsed time, and average pace. These metrics are additive optional version-1 fields: legacy version-1 reports decode them as `nil`, so the schema version remains 1 rather than introducing a needless breaking version. Encoding and decoding reuse separately synchronized JSON coders so concurrent callers remain Swift 6-safe without repeated coder setup.

## UI Design

### ReplayView
- `activeRival: ReplayRival?` replaces session-only `selectedGhostID`.
- `ReplayRivalControlView` owns selection/gap presentation and `Replay2DSceneView` owns Canvas/timeline state; the root retains import, race-result, renderer, playback, and export orchestration.
- Menu adds constant-pace and import actions; pace popover; balanced security-scope acquisition and release contained with bounded file reading and parsing in one detached import operation.
- A monotonic import generation token discards stale detached completions after a newer rival selection; task cancellation is propagated to the detached worker and checked during bounded reads plus the CSV, TCX, FIT, and normalization loops.
- Session-rival reconciliation returns immediately when the refreshed value is unchanged; changed trace or display metadata still invalidates the appropriate derived artifacts.
- `cachedRaceResult` recomputed only on rival (or detail) change; a library revision reconciles a selected session rival by session workout ID and trace fingerprint.
- A primary workout trace/axis identity owns the whole replay subtree, so a same-ID source refresh restarts playback, 2D, 3D, result, and report state together while unrelated library revisions do not interrupt replay. `WorkoutLibrary` computes and caches this O(N) identity when details change; SwiftUI only performs an O(1) lookup.
- Finish banner appears only at or after the player's interpolated distance-target crossing or the time-axis target duration; when a recorded trace ends fractionally before its summary duration, its reachable replay end is the finish gate. The separate 0.05-second epsilon applies only to tie classification and margin presentation.
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
- CSV scanning advances by Unicode scalar rather than extended grapheme cluster, coalesces CRLF as one delimiter, and preserves quoted Unicode and newline fields.
- TCX selects its XML code-unit layout once and scans the complete bounded input once for DOCTYPE; it does not truncate the security-sensitive prolog.
- Race-report JSON encoding and decoding reuse separate `Mutex`-protected coders.
- Race calculation O(N) once per rival selection.
- Past-session display/accessibility lookups use an initializer-built ID map rather than render-time array scans.
- 2D paths are precomputed by `ReplayRivalPathBuilder`; shorter rivals hold at the player finish, longer rivals interpolate at that cutoff, and dense visual traces are capped at 2,048 points while full traces remain available to race math.
- 3D pose contexts rebuilt only on rival identity change.
- Format-specific parsing and 2D/control rendering are split into focused files so the Phase 10B workflow does not accumulate in the parser facade or root replay view.

## Testing Strategy

- Source fixtures cover constant pace, CSV, TCX, base64 FIT, derived pace/watts, malformed/truncated input, and normalized time; result fixtures cover both winners, tie, non-zero origins, sparse interpolation, DNF, both axes, and non-finite sanitization.
- Core unit tests cover factory, every parser format/boundary, race result, and report completion/privacy semantics.
- Studio tests cover workflow construction, session-rival refresh/removal, bounded path generation, PNG signature, JSON privacy, and scene identity.
- Direct 3D coverage exercises the session genuine pose path, constant-pace/imported fallback, and production rival-change aggregate invalidation.
