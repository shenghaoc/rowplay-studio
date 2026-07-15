# Phase 10B - Complete Rival Workflow — Tasks

## Core

- [x] `ReplayRival` model
- [x] `ReplayRivalFactory` (session, constant pace distance/time, imported)
- [x] `ReplayRivalFileParser` (CSV, TCX, FIT; limits; normalization)
- [x] Streaming quote-aware CSV fields/newlines, strict XML TCX parsing, and compressed-timestamp FIT records
- [x] Reject malformed TCX/CSV and declared-payload FIT truncation
- [x] Trace-content identity for same-named imported-file replacement
- [x] `ReplayRaceResult` + calculator (distance crossing, time axis, DNF, ties)
- [x] `ReplayRaceReport` + builder + codec
- [x] Register parity fixtures in `Package.swift`

## Studio UI

- [x] Refactor `ReplayView` to generic `activeRival`
- [x] Constant-pace editor with `PaceInput`
- [x] File importer (CSV/TCX/FIT) with bounded read/parse off main actor
- [x] Cached race result; finish verdict banner
- [x] O(1) past-session label/verdict lookup in SwiftUI render paths
- [x] Save report / save card / share card
- [x] Single-action native share-sheet preparation at finish
- [x] Share-card invalidation on rival and appearance changes
- [x] Export minimization removes internal workout/session identifiers
- [x] `ReplayRaceCardView` + renderer + transfer items
- [x] `RealityReplaySceneView` generic rival + fallback articulation
- [x] Scene identity uses rival ID

## Tests

- [x] `ReplayRivalFactoryTests`
- [x] `ReplayRivalFileParserTests`
- [x] `ReplayRaceResultTests`
- [x] `ReplayRaceReportTests`
- [x] Extended `ReplayGhostWorkflowTests`
- [x] `ReplayRaceCardTests`
- [x] 3D / scene identity updates for rival ID

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
