# Phase 13 — Replay Motion Expressiveness

## Purpose

The 3D replay athlete reads as a mannequin. Every stroke is pose-identical;
only playback speed and the drive/recovery split vary between them.

The honest one-line summary: **the bundled production athlete path ignores the
phase-continuous motion graph that the procedural fallback already consumes, so
the high-quality renderer is driven by less information than the fallback it
replaced.** Everything else in this phase follows from that.

Four causes, all verified in the tree at `3d406a5`:

### C1. The production asset path is driven by less signal than the fallback

`ReplayMotionGraph` (`Sources/RowPlayCore/Replay/ReplayMotionGraph.swift`,
ported from web `motionGraph.ts`, bound by the `replay-current-main-motion.json`
parity fixture) exposes per-channel `value` / `velocity` / `acceleration` for
`spineHinge`, `torsoSwing`, `torsoReach`, `shoulderSet`, `headBob`, `armDraw`,
`legExtension`, and the SkiErg/BikeErg equivalents.

`ReplayRigPoseSolver` consumes it — `ReplayRigPose.swift` calls
`ReplayMotionGraph.sampleRower(pose:)` and reads `graph.body.spineHinge.value`.
So the procedural fallback rig and the 2D renderer are phase-continuous and
intensity-aware.

`grep -rn "MotionGraph" Sources/RowPlayStudio/Views/Replay3D/` returns nothing.
The Phase 11 bundled-V4 path — the high-quality path — samples a flat authored
clip and ignores the motion graph entirely.

### C2. Intensity and fatigue are computed and then discarded

`ReplayStrokePose` computes `intensity` (55% power / 30% DPS / 15% cadence),
`fatigue` (65% HR-derived / 25% progress / 10% high-intensity penalty), and
`amplitude` (clamped 0.72–1.32). Their entire contribution to the 3D scene is
one line in `Replay3DSceneBuilder.swift`:

```swift
let bob: Float = reduceMotion ? 0 : Float(sin(livePose.warpedPhase) * 0.06 * livePose.amplitude)
```

A 6 cm vertical bob. The 2D renderer uses `amplitude` in more places than the
3D one does.

### C3. Post-clip correction cannot reach the bones that carry effort

`ReplayAthleteContactRole` has exactly four cases — `leftHand`, `rightHand`,
`leftFoot`, `rightFoot` — plus pelvis alignment. `v4Spine`, `v4Chest`,
`v4Neck`, `v4Head`, and both clavicles are never written after clip sampling.
Layback angle, catch compression, head drop under fatigue, and shoulder set are
frozen across every stroke of every workout.

### C4. The phase warp has a velocity discontinuity at the finish

`ReplayAthletePhaseMap.clipFraction` was piecewise-linear in two segments: drive
onto `[0, clipDrive]`, recovery onto `[clipDrive, 1]`. C0 but not C1.
`driveFraction()` returns 0.28–0.46 depending on rate, power, and stroke
duration, while authored `driveEnd` is fixed at 0.38 (rower) and 0.34 (SkiErg).

| measured driveFrac | rower step | skierg step |
| --- | ---: | ---: |
| 0.28 | 36.5% | 24.5% |
| 0.34 / 0.38 (authored) | 0.0% | 0.0% |
| 0.46 | 39.0% | 65.4% |

The discontinuity lands on the catch/finish transition and vanishes only at the
exact rate where the estimator happens to return the authored value.

`ReplayAthletePhaseMap` is **not** bound by any web parity fixture. Its only
tests were the two hand-written cases in `ReplayAthletePhaseMapTests`. It is
native-owned and safe to change.

## Requirements

### R1. Continuous phase warp (13A)

- `clipFraction` is monotone for every `(sourceDrive, clipDrive)` pair on a
  dense grid across `[0.05, 0.95]²`, with no overshoot outside `[0, 1]` and no
  reversal.
- Landmarks hold: `f(0) = 0`, `f(sourceDrive) = clipDrive`, `f(1) = 1`, each to
  a stated tolerance.
- The numerically estimated first derivative is continuous at the drive/recovery
  seam within a stated tolerance, across the whole 0.28–0.46 `driveFrac` range
  and both authored `driveEnd` values.
- Non-finite and degenerate inputs return the existing clamped fallbacks.
- `isDrive` stays consistent with the mapping.
- No additive layer, no asset work, no renderer changes.

### R2. Additive motion-graph pose layer (13B)

- A pure, `Sendable`, Linux-testable Core type maps a `ReplayStrokePose` — and
  therefore the `ReplayMotionGraph` sample derived from it — onto bounded local
  rotation offsets for the semantic bones the contact solver does not own:
  `v4Spine`, `v4Chest`, `v4Neck`, `v4Head`, `v4LeftClavicle`,
  `v4RightClavicle`.
- Offsets are driven only by signal that already exists: `spineHinge`,
  `torsoSwing`, `shoulderSet`, `headBob`, plus `intensity`, `fatigue`, and
  `amplitude`. No second phase model, no parallel animation clock.
- Studio applies the offsets in `ReplayRigSource.apply(...)`, composed onto the
  sampled clip transform after `poseAdapter.apply(...)` and before
  `ReplayAthleteContactSolver.solve(...)`, so the contact solver reconciles
  hands and feet against the modified torso. One solve pass.
  `ReplayAthleteContactRole` is not widened.
- Every offset is bounded by explicit per-bone angular limits declared as Core
  constants.
- Reduced Motion returns the neutral pose exactly — the additive contribution is
  identically zero and the rendered skeleton is bit-identical to prior
  behaviour, proven by test.
- Existing contact residual tolerances still pass at every tier and sport; a
  dense full-cycle test per sport asserts the solve succeeds at low, median, and
  high intensity without `degenerateLimb` or `residualExceeded`.
- Identical `(pose, sport, quality)` inputs produce identical joint transforms
  across repeated seeks and across seek-away-and-back.
- Web parity fixtures still pass unmodified. The additive layer is native-only
  presentation on top of parity-bound signal and must not perturb the
  parity-bound values.
- Procedural fallback, 2D, and rival/ghost paths are unchanged in behaviour.

### R3. Per-stroke variation (13C)

- Bounded, deterministic micro-variation keyed on `ReplayStrokePose.index`, from
  a pure hash of stroke index and sport. No RNG, no wall clock, no frame count.
- Same workout replayed twice produces identical poses; the same stroke index
  always produces the same variation; seeking backward reproduces it exactly.
- Variation magnitude is bounded by declared Core constants, and is zero under
  Reduced Motion and under replay acceptance mode
  (`ROWPLAY_REPLAY_ACCEPTANCE=1`) so the Phase 12 acceptance harness stays
  deterministic.
- Contact residuals stay within tolerance across a dense cycle.
- A test shows stroke *n* and stroke *n+1* differ and that stroke *n* is stable
  across runs.

### R4. Frame-pacing measurement (13D, diagnostic only)

Phase 8D telemetry recorded, on the developer's own machine:

| tier | target interval | observed average | observed worst | scene update avg/worst |
| --- | ---: | ---: | ---: | --- |
| low (30 Hz) | 33.33 ms | 34.167 ms | 100.000 ms | 0.067 / 0.190 ms |
| medium (60 Hz) | 16.67 ms | 24.583 ms | 166.667 ms | 0.124 / 0.299 ms |
| ultra (60 Hz) | 16.67 ms | 27.222 ms | 216.666 ms | 0.191 / 0.360 ms |

Low meets its budget. Medium and Ultra miss theirs by 47–63%. Scene update cost
is under 0.4 ms — under 2% of the frame. The Phase 8D governor tunes course ring
segments, lane markers, wake entries, and droplet counts, none of which can
account for the missing ~24 ms.

- Determine where the frame time actually goes, using Instruments (Time Profiler
  and Animation Hitches / SwiftUI templates) against the staged bundle via
  `script/profile_replay.sh` and the Phase 12 acceptance harness. Establish
  specifically whether the cost sits in SwiftUI body re-evaluation through
  `TimelineView` and `Replay3DQualityRebuildBoundary`, in RealityKit's render,
  or elsewhere.
- Produce a written finding naming the dominant cost with measured numbers and
  the machine/OS it was measured on.
- State explicitly what could not be measured. Instruments profiling has been
  listed as unavailable evidence in Phases 8C, 8D, 10B, and 11; if it is
  unavailable again, say so plainly and stop rather than substituting inference
  for measurement.
- **No fix in this slice.** No quality tier, no budget adjustment, no view
  hierarchy restructuring. Propose the fix as Phase 14 scope.

### R5. Standing constraints

- Swift 6.3, macOS 26+, zero external dependencies. No toolchain, deployment
  target, or CI runner change.
- `RowPlayCore` imports no SwiftUI, AppKit, RealityKit, Combine, or Security.
  `RowPlayPlatform` imports no UI framework. Both architecture scans return no
  matches.
- All new pure math lives in Core with Linux-runnable tests.
- No bundled asset changes. No new USDZ, GLB, texture, or motion binary; no
  regeneration of `rowplay-motion.bin`. Upstream commit
  `4d96480e7c6fb382f800555bd3aa463d9fe5b1a6` stays pinned.
- Determinism is a product requirement: identical inputs produce identical poses
  across runs and machines. No wall-clock seeding, no `Date()`, no unseeded RNG,
  no floating-point accumulation across frames.
- Evidence that was unavailable is reported as unavailable, in the style already
  used by `docs/beta-readiness.md`.

## Non-goals

- Bluetooth, CoreBluetooth, FTMS, or Concept2 PM transport.
- iOS/iPadOS target work.
- New athlete, equipment, or environment assets; any asset regeneration.
- Localization.
- Notarization or Developer ID signing.
- External dependencies, toolchain changes, deployment-target changes.
- Any universal frame-rate guarantee or production-performance claim.
- New clips, facial or finger animation, secondary/cloth simulation, or leg IK
  beyond what the contact solver already does.
