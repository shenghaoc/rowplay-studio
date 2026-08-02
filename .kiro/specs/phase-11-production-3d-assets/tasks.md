# Phase 11 — Current RowPlay Parity: Stacked Tasks

Phase 11 is delivered as eight reviewable pull requests. A checked item means
that the corresponding layer has landed in its own stack branch; it does not
claim that the complete phase or visual QA matrix is finished.

- [x] **1/8 Reference bundle and provenance** — pin current RowPlay `main`,
      preserve manifests and hashes, add sync/export/conversion/validation
      tooling, and bundle the inert reference artifacts without replacing the
      existing runtime.
- [x] **2/8 Portable Core contracts** — add current motion tables, quaternion
      math, grip geometry and surfaces, hand closure, sport grip contracts,
      parity fixtures, and Linux-compatible tests.
- [x] **3/8 Equipment assets** — introduce per-sport native equipment assets,
      dimensional contracts, catalogs, libraries, providers, and atomic
      fallback while retaining the existing runtime until validation passes.
- [x] **4/8 Athlete runtime** — retain the pinned USDZ as the canonical
      rig/animation source; deterministically derive and validate eight actual
      GLB-colour material subsets; activate the athlete at every tier with the
      exact 0/128/256/512 process-shared detail ladder and independent
      live/rival materials; move portable cold-load preflight off `MainActor`;
      drive skeletal motion with deterministic exact seeking; and preserve the
      complete procedural-athlete fallback.
- [x] **5/8 Grip and contact** — integrate finger and thumb closure, contact
      solving, sport handle geometry, wrist orientation, release/recovery, and
      independent live/rival instances.
- [ ] **6/8 Replay 2D** — replace the timeline placeholder with the three sport
      renderers plus parity, accessibility, and Reduced Motion coverage.
- [ ] **7/8 Environments and quality** — add the three venue stories,
      materials, lighting profiles, quality-tier differentiation, and atomic
      environment fallback.
- [ ] **8/8 Camera, rival, effects, and final QA** — finish scene wiring and
      run the staged-app matrix across renderers, sports, tiers, themes, rival
      modes, and Reduced Motion before claiming Phase 11 acceptance.

Each layer must pass `git diff --check`, its focused tests, the full
warnings-as-errors build and test suite, and exact-head CI before merge.
