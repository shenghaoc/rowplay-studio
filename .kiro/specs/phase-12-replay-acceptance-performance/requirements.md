# Phase 12 — Production Replay Acceptance and Performance Hardening

## Purpose

Close the acceptance gap left after Phase 11:

- deterministic staged-app acceptance mode
- complete human 2D/3D visual matrix
- sustained production replay performance measurement
- evidence-backed visual/interaction/performance fixes only
- documentation truthfulness after Phase 11 merge
- a repeatable native release gate for later replay changes

This phase is not another athlete, equipment, environment, or motion rewrite.
Real Bluetooth, FTMS, and Concept2 PM transport remain deferred.

## Requirements

### R1. Deterministic acceptance mode

- Acceptance is active only when `ROWPLAY_REPLAY_ACCEPTANCE=1`.
- Environment values select sport, renderer, quality, camera, theme, rival,
  seek time, Reduced Motion, window size, and optional metrics output.
- Invalid values fail with fixed public diagnostics.
- Acceptance always uses deterministic demo workouts and never reads tokens or
  performs sync.
- Acceptance values never persist into normal user preferences.
- Acceptance is unreachable through normal user UI.

### R2. Production ReplayView reuse

- The acceptance harness constructs the production `ReplayView` from demo
  details and candidates.
- No parallel renderer or replay clock is introduced.
- The production accessibility tree and controls remain exposed.

### R3. Scenario catalog

- `script/replay_acceptance_scenarios.json` is the single catalog.
- Approximately 30–40 reviewed scenarios cover all sports, 2D/3D, all quality
  tiers, light/dark, rival absent/present, all cameras where relevant, Reduced
  Motion, compact/large windows, and representative contact phases.

### R4. Launch and profile scripts

- `script/launch_replay_acceptance.sh` launches `dist/RowPlayStudio.app` only.
- `script/profile_replay.sh` attaches `xctrace` when templates are available,
  samples resident memory, and writes repository-safe summaries.
- Trace bundles remain outside the repository.

### R5. Bounded acceptance metrics

- At most 600 steady-state samples per scenario.
- Summary includes average/p50/p95/p99/worst and samples above budget.
- No workout ID, token, account data, stroke values, or absolute private paths.
- Metrics emit only in acceptance mode and reuse production frame samples.

### R6. Human visual acceptance

- Full staged-app walkthrough for 2D and 3D across sports, themes, tiers,
  rivals, cameras, and window extremes.
- Compare intent against pinned RowPlay visual evidence without requiring pixel
  identity.

### R7. Evidence-backed fixes only

- Fix only defects demonstrated by visual or performance evidence.
- Each fix names failing scenario, baseline evidence, root cause, regression
  coverage, and post-fix evidence.

### R8. Truthful claim boundaries

- Do not claim GPU evidence, Instruments traces, spoken VoiceOver, exact screen
  sizes, or universal frame-rate guarantees when unavailable.
- Do not claim Bluetooth support or CI success before exact-head CI completes.
