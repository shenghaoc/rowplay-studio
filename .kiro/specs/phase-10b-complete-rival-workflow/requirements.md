# Phase 10B - Complete Rival Workflow — Requirements

## Purpose

Complete the rival workflow started in Phase 10A as one unit: retain past-session rivals; add constant-pace and imported CSV/TCX/FIT rivals; correct finish and winner/verdict semantics; add privacy-safe local race report and race-card export/share; support all rival types in 2D and 3D; correct stale roadmap status for merged Phases 8D and 10A.

No network service or public share URL is required. “Share” means native local export and the macOS share sheet.

## Requirements

### R1: Generic Rival Model
- Portable `ReplayRival` in RowPlayCore for past session, constant pace, and imported file.
- Stable identifier suitable for SwiftUI and 3D scene identity.
- Rival kind, local display label, `[Stroke]`, genuine-stroke flag, optional session workout ID, optional target pace.
- No tokens, full filesystem paths, hardware identifiers, or account data.
- Imported filename (last path component only) may appear in local UI only.

### R2: Rival Factory
- Convert past-session `WorkoutDetail` to rival.
- Create constant-pace rival for distance-axis (finish at target distance) and time-axis (run for target duration).
- Convert parsed imported traces to rivals.
- Two samples for constant pace (interpolation).
- Sport-aware watts via `RowPlayFormatting.paceToWatts(for:pacePer500m:)`.
- Constant-pace and imported rivals mark `hasGenuineStrokeData = false`.
- Reject zero, negative, NaN, infinite, or overflowing inputs.

### R3: CSV / TCX / FIT Import
- Portable, dependency-free `ReplayRivalFileParser`.
- Accept `Data` plus last path component; detect FIT by signature/extension, TCX by extension/XML, else CSV.
- Limits: 25 MiB, 200_000 samples.
- CSV: flexible headers, RFC 4180-style quoted fields, clock formats, derived pace/watts.
- TCX: namespace-insensitive trackpoints; relative timestamps.
- FIT: bounded record-message parser without external SDK.
- Normalize time to zero, remove invalid samples, require ≥2 samples.
- Never log file contents or paths.

### R4: Race Target and Result Semantics
- Outcomes: player won, rival won, tie.
- Distance-axis: interpolated target crossing (not array endpoints); 0.05 s tie; DNF when rival never reaches target; no verdict if player never reaches target.
- Time-axis: sample at target duration; greater distance wins; 0.5 m tie; no time margin.
- O(N), deterministic, independent of SwiftUI.

### R5: Replay UI
- One generic active rival preserving Phase 10A past-session behavior.
- Menu: No Rival, Best Match, ranked sessions, Set Constant Pace…, Import Rival File….
- Pace editor uses `PaceInput`; invalid pace does not replace current rival.
- File import via `.fileImporter` with security-scoped access; parse off main actor.
- Rival change preserves time, play/pause, speed, renderer, camera, quality; increments discontinuity; rebuilds 2D path; clears 3D rival effect state; caches race result once.

### R6: 2D and 3D Rendering
- 2D uses generic rival strokes; live path dominant; path derivation outside Canvas.
- 3D accepts generic rival; genuine stroke data uses stroke-accurate articulation; others use fallback.
- Scene identity includes generic rival ID.
- No second replay clock or renderer.

### R7: Finish Verdict
- Reveal only after primary workout finish.
- Show Race Finished, winner/tie, rival description, margins, DNF wording.
- Past-session includes date; constant pace identifies pace boat; exported/shared wording uses “Imported rival” (filename live UI only).
- Combined accessibility label/value; not color alone.
- Seek backward hides verdict until finish again; cached result retained.

### R8: Race Export and Share
- Versioned Codable `ReplayRaceReport` privacy-safe JSON.
- Native race card PNG via ImageRenderer/AppKit in Studio.
- Save Race Report…, Save Race Card…, Share Race Card (macOS share sheet).
- Race-card share data is prepared when the verdict appears so Share Race Card opens in one action.
- No public URL or network work.

### R9: Architecture, Privacy, Performance, Accessibility
- RowPlayStudio → RowPlayPlatform → RowPlayCore; no forbidden Core/Platform imports.
- Swift 6.3, macOS 26+, zero dependencies; no toolchain/CI/package graph changes.
- Parsing bounded and off main actor; O(N) race math; cached paths/results.
- Tokens Keychain-only; no sensitive logging.
- Keyboard, labels, Reduced Motion, deterministic demo mode preserved.

### R10: Tests and Fixtures
- Fixtures: `replay-rival-sources-parity.json`, `replay-race-result-parity.json`.
- Tests: factory, parser, race result, race report, ghost workflow, race card, 3D rival coverage.

### R11: Documentation
- Kiro requirements/design/tasks for Phase 10B as one unit (no 10B1/10B2/10B3).
- Update roadmap (8D=#58, 10A=#61, 10B complete on this branch), source-map, beta-readiness.

## Non-Goals
- Public URLs, network rivals, persisted rival selection, deep links, leaderboards, OAuth, Bluetooth, external dependencies, full FIT SDK, GPX, new 3D assets, rig redesign, unrelated UI redesign, toolchain/CI changes.
