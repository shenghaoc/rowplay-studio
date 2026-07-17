# Phase 10B - Complete Rival Workflow — Requirements

## Purpose

Complete the rival workflow started in Phase 10A as one unit: retain past-session rivals; add constant-pace and imported CSV/TCX/FIT rivals; correct finish and winner/verdict semantics; add privacy-safe local race report and race-card export/share; support all rival types in 2D and 3D; correct stale roadmap status for merged Phases 8D and 10A.

No network service or public share URL is required. “Share” means native local export and the macOS share sheet.

## Requirements

### R1: Generic Rival Model
- Portable `ReplayRival` in RowPlayCore for past session, constant pace, and imported file.
- Stable identifier suitable for SwiftUI and 3D scene identity; session and imported identities include normalized trace content so a refreshed same-ID session or replacement same-named file refreshes derived state.
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
- Constant-pace identity preserves the exact accepted pace and target so nearby valid inputs cannot reuse stale derived UI or 3D state.
- Reject zero, negative, NaN, infinite, or overflowing inputs.

### R3: CSV / TCX / FIT Import
- Portable, dependency-free `ReplayRivalFileParser` returning a normalized trace or typed error.
- Accept `Data` plus last path component; detect FIT by a plausible bounded header/signature or extension, TCX by extension/XML content, else CSV. A misleading filename extension does not override a valid recognized payload.
- Limits: 25 MiB, 200_000 samples.
- CSV: flexible headers, streaming RFC 4180-style quoted fields (including embedded newlines), clock formats, derived pace/watts, and malformed-quote rejection.
- TCX: namespace-aware XML parsing with namespace-insensitive trackpoints, encoding-independent DTD/entity rejection, strict malformed-document rejection, timezone-qualified timestamps plus timezone-less UTC fallback, and relative timestamps after sorting.
- FIT: bounded record-message parser without external SDK; timestamp, distance, speed/enhanced-speed, power, cadence, and heart-rate fields; declared payload truncation, invalid definition architectures, and unknown message definitions fail safely.
- Normalize time to zero; sort where the format requires it; collapse equal timestamps deterministically; drop negative, non-finite, backward-distance, and otherwise invalid samples; preserve only finite values; cap output; require at least two samples.
- Never log file contents or paths.

### R4: Race Target and Result Semantics
- Outcomes: player won, rival won, tie.
- Distance-axis: first interpolated target crossing (not array endpoints); 0.05 s tie; absolute time margin; loser distance shortfall sampled at the winner's finish; rival DNF is a player win with shortfall at player finish; no result if the player never reaches target.
- Time-axis: sample both traces at target duration; greater distance wins; 0.5 m tie; absolute distance margin; no time margin.
- Every result number is finite and non-negative.
- O(N), deterministic, independent of SwiftUI.

### R5: Replay UI
- One generic active rival preserving Phase 10A past-session behavior.
- Menu: No Rival, Best Match, ranked sessions, Set Constant Pace…, Import Rival File….
- Pace editor defaults to the workout's average pace and uses `PaceInput`; invalid pace shows a clear validation error and does not replace the current rival.
- File import via `.fileImporter` with balanced security-scoped access in the detached bounded read/parse operation, without first loading an oversized file in full.
- Import shows progress; cancellation and failure preserve the active rival; user-facing failures are actionable and never expose a local path.
- A newer manual rival choice cancels the detached worker and invalidates any older in-flight import completion.
- Rival change preserves time, play/pause, speed, renderer, camera, quality; increments discontinuity; rebuilds 2D path; clears 3D rival effect state; caches race result once.
- Session-rival selection refreshes or clears when the cached library candidate with that workout ID changes or disappears.
- The live gap display works for every rival kind.

### R6: 2D and 3D Rendering
- 2D uses generic rival strokes; the live workout remains visually dominant; path derivation stays outside Canvas; shorter traces hold their endpoint, longer traces interpolate at the player finish, and dense visual paths are bounded without changing race math.
- 3D accepts generic rival; genuine stroke data uses stroke-accurate articulation; non-genuine traces use deterministic fallback while preserving the separate rival lane, translucent styling, wake/effect behavior, camera presets, adaptive-quality controls, and Reduced Motion behavior.
- The inner RealityKit graph identity includes the generic rival ID while camera, orbit, and adaptive-quality owners remain outside that rebuild boundary; the stable outer owner is keyed by workout and sport so cached live aggregates cannot cross workouts.
- No second replay clock or renderer.

### R7: Finish Verdict
- Reveal only after primary workout finish.
- Show Race Finished, winner/tie, rival description, margins, DNF wording.
- Past-session includes date; constant pace identifies pace boat; exported/shared wording uses “Imported rival” (filename live UI only).
- Combined accessibility label/value; not color alone.
- Seek backward hides verdict until finish again; cached result retained.

### R8: Race Export and Share
- Versioned Codable `ReplayRaceReport` privacy-safe JSON containing schema/version, export date, sport, distance-or-duration target, the primary completion summary, sanitized rival kind/metrics, outcome, and time/distance margins.
- Distance-axis primary metrics use the target distance and player's interpolated target-crossing time; time-axis primary metrics use player distance at target duration and that duration. Winner-decision shortfall snapshots remain result margins rather than replacing the primary completion summary.
- Rival summaries include finite, non-negative distance/time and a finite positive pace when derivable from the completed result; these are additive optional version-1 fields so reports written before the fields existed remain decodable.
- Exported reports/cards and their suggested filenames omit imported filenames and internal workout/session identifiers; past-session cards use the session date.
- Native race card PNG via ImageRenderer/AppKit in Studio with light and dark appearance support.
- Metric-rich race cards keep the accent, content, and footer inside the fixed export canvas and omit decorative separators from their explicit accessibility summary.
- Save Race Report…, Save Race Card…, Share Race Card (macOS share sheet).
- Race-card share data is prepared when the verdict appears so Share Race Card opens in one action.
- Rival and appearance changes invalidate and rebuild prepared share-card data.
- No public URL or network work.

### R9: Architecture, Privacy, Performance, Accessibility
- RowPlayStudio → RowPlayPlatform → RowPlayCore; no forbidden Core/Platform imports.
- Swift 6.3, macOS 26+, zero dependencies; no toolchain/CI/package graph changes.
- Parsing bounded and off main actor; O(N) race math; cached paths/results; no O(N) work in SwiftUI body or Canvas/RealityKit per-frame closures; no unbounded histories.
- Tokens Keychain-only; no sensitive logging.
- Keyboard operation, Reduced Motion, deterministic demo mode, and non-genuine rival usability in Reduced Motion/automation are preserved.
- Rival menu, pace editor, import action, verdict, export actions, and errors have explicit accessibility labels; disabled actions explain why they are unavailable.

### R10: Tests and Fixtures
- Source fixtures cover constant pace, CSV, TCX, base64 FIT, derived pace/watts, malformed/truncated input, and time normalization.
- Result fixtures cover both winners, tie, non-zero timestamp origins, sparse interpolation, shorter-rival/DNF, both axes, and non-finite sanitization.
- Tests cover factory, parser, race result, race report, ghost workflow, race-card PNG/signature plus JSON/privacy behavior, and direct 3D session-genuine, pace/import fallback, and rival-change state-clearing behavior.

### R11: Documentation
- Kiro requirements/design/tasks for Phase 10B as one unit (no 10B1/10B2/10B3).
- Update roadmap (8D=#58, 10A=#61, 10B complete on this branch), source-map, beta-readiness.

## Non-Goals
- Public URLs, network rivals, persisted rival selection, deep links, leaderboards, OAuth, Bluetooth, external dependencies, full FIT SDK, GPX, new 3D assets, rig redesign, unrelated UI redesign, toolchain/CI changes.
