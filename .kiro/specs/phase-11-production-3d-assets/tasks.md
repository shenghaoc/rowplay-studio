# Phase 11 — Current RowPlay Parity: Stacked Tasks

Phase 11 delivered as eight reviewable pull requests and merged to `main`
through PRs #90–#97. A checked item means the corresponding layer landed and
merged. Automated matrices shipped with layer 8/8; the complete human visual
and sustained-profiling acceptance gate is Phase 12.

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
      solving, independent sculls, course skis/poles, road-bike contact
      geometry, wrist orientation (superseded: Phase 12 removed the fixed-axis
      terminal twist in favour of the clip's authored wrist/ankle orientation),
      release/recovery, complete authored
      composites at High/Ultra, and independent live/rival instances.
- [x] **6/8 Replay 2D** — replace the timeline placeholder with the three sport
      renderers plus parity, accessibility, and Reduced Motion coverage.
- [x] **7/8 Environments and quality** — add the three venue stories,
      BikeErg line grammar, per-sport/theme lighting, primary-receiver
      materials, planar native-course mapping, and quality-tier differentiation.
      Environment geometry is non-failable; individual texture slots retain
      scalar PBR when a bundled map is unavailable.
- [x] **8/8 Camera, rival, effects, and final QA** — finish scene wiring and
      add 48 procedural wiring cases across sports, tiers, cameras, varied
      aspects, and the shared rival predicate, plus 48 deterministic
      theme/rival cases covering bundled-path eligibility, Reduced Motion,
      exact seeks, and chase framing. A staged-bundle launch and the separate
      human renderer walkthrough remain explicit pre-acceptance gates rather
      than claims made by this checkbox.

Each layer must pass `git diff --check`, its focused tests, the full
warnings-as-errors build and test suite, and exact-head CI before merge.
