# Phase 12 Tasks

- [x] **1. Deterministic acceptance configuration** — `ReplayAcceptanceConfiguration`,
      launch wiring, harness, and non-persisting `ReplayView` initial configuration.
- [x] **2. Scenario catalog and launch script** — reviewed 37-scenario matrix,
      `launch_replay_acceptance.sh`, and narrow `build_and_run.sh --acceptance`.
- [x] **3. Bounded acceptance metrics** — 600-sample recorder, percentiles,
      privacy-safe emit path, production sample reuse (fixed to every paired sample).
- [x] **4. Profile script** — Time Profiler attach when available, RSS sampling,
      repository-safe summaries, no committed trace bundles.
- [x] **5. Focused tests** — configuration, harness, metrics, and related
      automation readiness coverage with warnings-as-errors.
- [x] **6. Baseline staged-app matrix** — catalog launches and pre/post metrics
      evidence recorded under `/tmp` and summarized in visual-QA docs.
- [x] **7. Human visual acceptance** — staged launches across sports/renderers/
      tiers/rivals/cameras/Reduced Motion/windows; screenshot PNG commit blocked
      by Screen Recording TCC (documented unavailable).
- [x] **8. Evidence-backed fixes** — metrics pairing under-sampling fixed with
      before/after sample counts; no unjustified scene rewrites.
- [x] **9. Sustained profiling** — Ultra+rival 60s per sport with Time Profiler;
      Metal System Trace listed but not attached; honest GPU status recorded.
- [x] **10. Durable validation** — full test/build, architecture scans, staged
      `--verify`/`--automation`/`--sign-verify`.
- [x] **11. Documentation** — Phase 12 Kiro spec, roadmap, source-map,
      beta-readiness, Phase 11 status corrections, visual-QA README/manifest.
- [ ] **12. Draft PR** — single PR with complete evidence sections; remains draft
      until exact-head CI and review complete.
