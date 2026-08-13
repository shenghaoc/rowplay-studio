# Phase 13 Tasks

## 13A — Continuous phase warp (`phase-13a-continuous-phase-warp`)

- [x] **1. Monotone C1 clip-fraction map** — replace the two-segment linear map
      with a pair of cubic Hermite segments sharing the PCHIP weighted-harmonic
      tangent. Landmarks unchanged, clamped fallbacks unchanged.
- [x] **2. Consistent drive predicate** — `isDrive` resolves `authoredDriveEnd`
      through the same clamp the map uses, so the predicate cannot disagree with
      the mapping on non-finite or out-of-range authored values.
- [x] **3. Tests** — dense 91 × 91 × 400 monotonicity/range/landmark grid,
      seam and wrap slope continuity across the production range and the full
      clamped square, the O(h) shrink signature, the drive-share identity case,
      degenerate clamping, and `isDrive` agreement over the grid. Ten net new
      Core tests; the two pre-existing tests are retained with one assertion
      changed and justified in `design.md`.
- [x] **4. Documentation** — this spec, plus roadmap (including the correction
      that Phase 12 merged as PR #103), source-map, and beta-readiness updates in
      the same diff.
- [x] **5. Validation** — Core and full build/test with
      `-Xswiftc -warnings-as-errors`, both architecture scans,
      `git diff --check`, and staged `--verify` / `--automation` /
      `--sign-verify`.
- [ ] **6. PR** — open `phase-13a-continuous-phase-warp` against `main`.

## 13B — Additive motion-graph pose layer (`phase-13b-additive-motion-layer`)

- [ ] **1. Core `ReplayAthleteAdditivePose`** — bounded per-bone rotation
      offsets from existing motion-graph channels and `intensity` / `fatigue` /
      `amplitude`; per-bone angular limits as Core constants.
- [ ] **2. Studio application** — compose in `ReplayRigSource.apply(...)` after
      `poseAdapter.apply(...)` and before the contact solve. No second solve
      pass, no widened `ReplayAthleteContactRole`.
- [ ] **3. Reduced-Motion neutrality** — additive contribution identically zero,
      proven by test rather than asserted in prose.
- [ ] **4. Contact and determinism tests** — dense full-cycle solve per sport at
      low/median/high intensity, no `degenerateLimb` or `residualExceeded`,
      residuals within existing tolerances, identical transforms across repeated
      and shuffled seeks.
- [ ] **5. Parity** — `replay-current-main-motion.json`, `stroke-pose-parity.json`,
      and the grips/equipment/2D fixtures pass unmodified.
- [ ] **6. Validation and visual matrix** — full gates plus three sports × 2D/3D
      × Reduced Motion on/off, at minimum one low and one ultra tier, with pause,
      forward seek, and backward seek. Record what was observed and what was not
      reachable.
- [ ] **7. Documentation and PR**.

## 13C — Per-stroke variation (`phase-13c-per-stroke-variation`)

- [ ] **1. Deterministic hash** — pure integer hash of stroke index and sport;
      no RNG, no wall clock, no frame count.
- [ ] **2. Bounded variation** — magnitudes declared as Core constants; zero
      under Reduced Motion and under `ROWPLAY_REPLAY_ACCEPTANCE=1`.
- [ ] **3. Tests** — stroke *n* differs from *n+1*; stroke *n* is stable across
      runs and across backward seeks; contact residuals hold across a dense
      cycle.
- [ ] **4. Validation, visual matrix, documentation, PR**.

## 13D — Frame-pacing measurement (`phase-13d-frame-pacing-measurement`)

- [ ] **1. Profiling run** — Instruments Time Profiler and Animation Hitches /
      SwiftUI templates against `dist/RowPlayStudio.app` through
      `script/profile_replay.sh` and the Phase 12 acceptance harness.
- [ ] **2. Written finding** — dominant cost with measured numbers and the
      machine/OS measured on; explicit statement of what could not be measured.
- [ ] **3. Phase 14 proposal only** — no quality tier, no budget change, no view
      hierarchy restructuring in this slice.
