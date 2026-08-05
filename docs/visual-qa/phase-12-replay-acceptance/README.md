# Phase 12 — Replay Acceptance and Performance

## Scope

Deterministic staged-app acceptance mode, reviewed scenario catalog (37 cases),
bounded metrics, Time Profiler + RSS profiling, documentation corrections after
Phase 11 merge (PRs #90–#97), and evidence-backed fixes only.

## Environment

| Field | Value |
| --- | --- |
| Machine model | Mac17,2 |
| macOS | 27.0 |
| Baseline branch tip before Phase 12 commit | `f7170f5` (origin/main) |
| Bundled RowPlay reference | `4d96480e7c6fb382f800555bd3aa463d9fe5b1a6` (matches web main) |
| App under test | `dist/RowPlayStudio.app` only |

## Acceptance configuration

- Flag: `ROWPLAY_REPLAY_ACCEPTANCE=1`
- Catalog: `script/replay_acceptance_scenarios.json` (37 scenarios)
- Launch: `./script/launch_replay_acceptance.sh --scenario <ID>`
- Profile: `./script/profile_replay.sh --scenario <ID> --duration <s> --output <DIR>`
- Demo workouts: rower `1001`, skierg `1003`, bike `1004`
- No preference persistence; no token/sync

## Baseline before rendering fixes

No production 2D/3D rendering, camera, contact, or lifecycle defect was
demonstrated that required changing scene code. The only evidence-backed code
defect found during the matrix was acceptance-metrics sampling wiring (paired
samples were recorded only when a production 120-sample window completed).

### Metrics sampling defect

| | Before | After |
| --- | --- | --- |
| Scenario | `rower-3d-ultra-session-rival` 60s | same |
| Sample count | 8–9 | 600 (cap) |
| Root cause | `ReplayAcceptanceMetricsStore.recordPairedSample` ran only after a completed production metrics window | Record every production paired sample |
| File | `ReplayPerformanceController.swift` | same |

## Human visual matrix

### Method

- Launched all 37 catalog IDs via the staged app script (process verified).
- Representative scenarios held for interactive inspection: all three sports in
  2D and 3D Ultra+session-rival, High solo, Reduced Motion, compact/large
  window IDs, and all four cameras through dedicated catalog entries.
- Phase 11 automated 48+48 scene matrices remain green and cover wiring,
  seek identity, Reduced Motion FOV, and rival framing.
- Full-display `screencapture` was attempted; **Screen Recording permission was
  unavailable**, so no committed screenshot PNGs are claimed.

### 2D by sport

| Sport | Result | Notes |
| --- | --- | --- |
| RowErg | Pass (launch + automated 2D suite) | Shell/athlete/seat/sculls remain the production Phase 11 path; no regression to graph+dot observed in staged launch |
| SkiErg | Pass (launch + automated 2D suite) | Outdoor stadium path; no indoor tower fallback observed at launch |
| BikeErg | Pass (launch + automated 2D suite) | Velodrome + bicycle path; rival session scenarios launch cleanly |

### 3D by sport

| Sport | Result | Notes |
| --- | --- | --- |
| RowErg Ultra+rival | Pass | Process stable 60s; no fallback category; no quality oscillation |
| SkiErg Ultra+rival | Pass | Same |
| BikeErg Ultra+rival | Pass | Same; slightly higher over-budget sample count still without adaptive degrade |

### Quality tiers

Low/Medium/High/Ultra catalog entries all launch. Production athlete remains
the Phase 11 path at every tier; Low/Medium retain procedural equipment policy
by design. No tier transition oscillation observed in Ultra profiles
(`adaptiveDegradationCount=0`, `sceneRebuildCount=0`).

### Rival / camera

Session and pace rivals resolve from deterministic demo candidates. Chase,
side, overhead, and orbit catalog entries launch. Reduced Motion catalog
entries launch without auto-play motion when `reducedMotion=true`.

## Performance evidence (post metrics-wiring fix)

Time Profiler template: **recorded** for Ultra scenarios.
Metal System Trace: **listed** by `xcrun xctrace list templates` but **not
attached** for a second full-duration run (honest status:
`template-listed-not-attached:Metal System Trace`).
Trace bundles remain under `/tmp` only.

| Scenario | Samples | p95 frame ms | p95 scene ms | Over budget | RSS last | Degrade | Rebuilds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| rower-3d-ultra-session-rival 60s | 600 | 16.67 | 0.55 | 6 | ~264 MiB | 0 | 0 |
| skierg-3d-ultra-session-rival 60s | 600 | 16.67 | 0.47 | 3 | ~275 MiB | 0 | 0 |
| bike-3d-ultra-session-rival 60s | 600 | 16.67 | 0.37 | 19 | ~319 MiB | 0 | 0 |

Observations (this machine only, not universal guarantees):

- Steady frame interval clusters at ~16.67 ms (60 Hz display cadence).
- Scene-update p95 stays sub-millisecond on the measured path.
- RSS rises during scene warm-up then plateaus within the sample window; no
  unbounded steady-state growth signature in the 12-sample RSS series.
- 2D scenarios correctly emit zero RealityKit paired samples.

## Evidence-backed fixes

1. **Acceptance metrics under-sampling** — every production paired sample now
   feeds the bounded 600-cap recorder (see table above).
2. **Acceptance auto-play** — non–Reduced-Motion acceptance scenarios call
   `ReplayState.play()` so profiling is not idle.
3. **`ReplayRendererMode: Sendable`** — required for Sendable acceptance
   configuration under Swift 6.

No camera FOV, contact, material, equipment, environment, or motion-contract
changes were required by demonstrated defects.

## Accessibility and Reduced Motion

- Harness reuses production `ReplayView` controls and accessibility labels/hints
  (including PR #102 icon-control hints).
- Acceptance mode is not a separate renderer and adds no VoiceOver-visible
  diagnostics overlay.
- Reduced Motion scenarios force calm pose without preference persistence.
- **Spoken VoiceOver pass: not performed.**

## Unavailable evidence

- Spoken VoiceOver walkthrough
- Exact 1440×900 inspection (desktop may not host that size)
- Trackpad gesture proof
- Metal System Trace / GPU hardware counters (template listed, not attached)
- Committed pixel screenshots (Screen Recording TCC unavailable to the agent)
- Universal frame-rate guarantees across machines

## Claim boundary

Phase 12 ships a **repeatable release gate** and records same-machine evidence.
It does not claim new athlete/asset quality work, Bluetooth, or CI green before
exact-head checks complete.
