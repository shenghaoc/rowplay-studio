# Phase 10B - Complete Rival Workflow — Tasks

## Core

- [x] `ReplayRival` model
- [x] `ReplayRivalFactory` (session, constant pace distance/time, imported)
- [x] `ReplayRivalFileParser` (CSV, TCX, FIT; limits; normalization)
- [x] Split parser facade, CSV, TCX, FIT, and shared support into focused files
- [x] Streaming quote-aware CSV fields/newlines, strict XML TCX parsing, and compressed-timestamp FIT records
- [x] Unicode-scalar CSV scanning with quoted Unicode and CRLF regression coverage
- [x] Direct CR/LF/CRLF delimiter handling without grapheme construction
- [x] Reject malformed TCX/CSV and declared-payload FIT truncation
- [x] Reject encoding-independent TCX DTD/entity declarations and invalid FIT definition architectures
- [x] Deterministically collapse duplicate timestamps and preserve exact constant-pace identities
- [x] Trace-content identity for same-named imported-file replacement
- [x] Checked formatting for extreme finite telemetry and positive sub-metre race margins
- [x] `ReplayRaceResult` + calculator (distance crossing, time axis, DNF, ties)
- [x] Reject empty and single-stroke race-result inputs at the public boundary
- [x] Strict finish gate with reachable time-axis end and tie epsilon limited to classification/margins
- [x] `ReplayRaceReport` + builder + codec
- [x] Swift 6-safe synchronized reuse of race-report JSON coders
- [x] Additive version-1 rival distance/time/pace metrics with legacy decode coverage
- [x] Register parity fixtures in `Package.swift`

## Studio UI

- [x] Refactor `ReplayView` to generic `activeRival`
- [x] Extract rival controls and 2D timeline/canvas state from the root replay view
- [x] Constant-pace editor with `PaceInput`
- [x] File importer (CSV/TCX/FIT) with bounded read/parse off main actor
- [x] Cancellable stale-import guard and colocated security-scope lifetime
- [x] Cooperative cancellation through CSV, TCX, FIT, and normalization work
- [x] Cached race result; finish verdict banner
- [x] No-op session-rival reconciliation avoids redundant result/share-card work
- [x] O(1) past-session label/verdict lookup in SwiftUI render paths
- [x] Cached primary trace/axis identity with O(1) replay-subtree keying
- [x] Exclude unusable one-stroke sessions from cached rival candidates
- [x] Save report / save card / share card
- [x] Single-action native share-sheet preparation at finish
- [x] Share-card invalidation on rival and appearance changes
- [x] Export minimization removes internal workout/session identifiers
- [x] Generic privacy-safe suggested export filenames
- [x] `ReplayRaceCardView` + renderer + transfer items
- [x] Privacy-safe rival result metrics on session, pace-boat, and imported cards
- [x] Fixed-canvas metric-card layout and decorative-separator accessibility coverage
- [x] Verdict accessibility grouping keeps save/share buttons independently operable
- [x] `RealityReplaySceneView` generic rival + fallback articulation
- [x] Scene identity uses rival ID
- [x] Rival graph rebuild preserves camera, orbit, and adaptive-quality owners
- [x] Workout/sport outer identity resets cached live 3D aggregates
- [x] Correct and bounded shorter/longer 2D rival path geometry

## Tests

- [x] `ReplayRivalFactoryTests`
- [x] `ReplayRivalFileParserTests`
- [x] `ReplayRaceResultTests`
- [x] `ReplayRaceReportTests`
- [x] Extended `ReplayGhostWorkflowTests`
- [x] `ReplayRaceCardTests`
- [x] Direct 3D session-genuine pose, constant-pace/import fallback, and production rival-change aggregate invalidation tests

## Documentation

- [x] Kiro requirements / design / tasks (single Phase 10B unit)
- [x] `docs/roadmap.md` — 8D=#58, 10A=#61, Phase 10B complete on branch
- [x] `docs/source-map.md` sources / race result / race card mappings
- [x] `docs/beta-readiness.md` Phase 10A merged; Phase 10B capability

## Validation

- [x] Focused swift tests (factory, parser, result, report, ghost, card, 3D)
- [x] Architecture import scans
- [x] Full `swift test` / `swift build` / `git diff --check`
- [x] Staged app `--verify` / `--automation` / `--sign-verify`
- [x] Diff audit and ready-for-review PR
