# Phase 13 Design — Replay Motion Expressiveness

Delivered as four stacked slices, each its own branch and PR:

| Slice | Branch | Scope |
| --- | --- | --- |
| 13A | `phase-13a-continuous-phase-warp` | C1 phase warp (Core only) |
| 13B | `phase-13b-additive-motion-layer` | Additive motion-graph pose layer |
| 13C | `phase-13c-per-stroke-variation` | Deterministic per-stroke variation |
| 13D | `phase-13d-frame-pacing-measurement` | Frame-pacing measurement, diagnostic only |

13D is independent of 13A–13C. 13C depends on 13B.

Dependency direction stays `RowPlayStudio → RowPlayPlatform → RowPlayCore`. All
new math is pure Core with Linux-runnable tests. No new dependencies, no
toolchain change, no asset change.

---

## 13A — Continuous phase warp

Status: implemented.

### Problem

`ReplayAthletePhaseMap.clipFraction` re-times one native stroke cycle onto the
authored clip's drive/recovery split. Both drive shares vary independently:

- native `sourceDrive` = `ReplayStrokePose.driveFrac`, clamped to
  `[0.28, 0.46]` for RowErg and SkiErg and fixed at `0.50` for BikeErg;
- authored `clipDrive` = the manifest's `driveEnd`, fixed at `0.38` rower,
  `0.34` SkiErg, `0.50` bike.

The previous map was two linear segments joined at `(sourceDrive, clipDrive)`.
Its playback speed is the segment secant, so it steps at the seam by
`|Δrecovery − Δdrive| / Δdrive` — 24.5% to 65.4% over the production range. It
steps a second time at the cycle wrap, in the opposite direction, because
`Δdrive` and `Δrecovery` meet again there.

### Construction chosen: monotone cubic Hermite, PCHIP tangent

Three landmarks must be hit exactly: `f(0) = 0`, `f(s) = d`, `f(1) = 1`, where
`s = sourceDrive` and `d = clipDrive`. Two cubic Hermite segments interpolate
them. The endpoint tangents decide both continuity and monotonicity.

The tangent is the Fritsch–Butland (PCHIP) weighted harmonic mean of the two
adjacent secants. With `h_left` and `h_right` the adjacent interval lengths, the
weights are `w₁ = 2·h_right + h_left` against the left secant and
`w₂ = h_right + 2·h_left` against the right, and `w₁ + w₂ = 3` because the cycle
has unit length.

Evaluating that at each knot of this two-segment cycle:

- interior knot `s`: `h_left = s`, `h_right = 1 − s`, so
  `w₁ = 2 − s` against `Δdrive` and `w₂ = 1 + s` against `Δrecovery`;
- wrap knot `0 ≡ 1`: the intervals swap, so `w₁ = 1 + s` against `Δrecovery`
  and `w₂ = 2 − s` against `Δdrive`.

Both evaluate to the same number:

```
m = 3 / ( (2 − s)/Δdrive + (1 + s)/Δrecovery )
```

So a **single shared tangent** makes the map C1 at the drive/recovery seam *and*
across the cycle wrap. That coincidence is specific to a two-knot cyclic map and
is why this construction was chosen over a slope-blended one: it needs no
separate end-condition rule, and periodicity falls out rather than being
imposed.

### Continuity class achieved

**C1 on the cycle, treated as a circle.** Not C2 — the second derivative still
steps at both knots, which is inaudible as playback speed and is what every
PCHIP-class interpolant gives.

For a segment with equal endpoint tangents:

```
H(u) = y₀ + span · ( Δ·(3u² − 2u³) + m·(2u³ − 3u² + u) )
H′(x) = m + 6u(1 − u)·(Δ − m)
```

`H′` equals `m` at both ends of both segments, which is the C1 property, and it
is a single value at the seam instead of a step.

### Monotonicity

`H′(x) = m + 6u(1−u)(Δ − m)` with `u(1−u) ∈ [0, ¼]`, so

```
min H′ = min( m, 1.5·Δ − 0.5·m )
```

which is positive exactly when `0 < m < 3Δ`. The PCHIP weights give that
strictly: `m ≤ 3Δdrive` reduces to `(1−s)/Δdrive + (1+s)/Δrecovery ≥ 0`, and
`m ≤ 3Δrecovery` to `(2−s)/Δdrive + s/Δrecovery ≥ 0`. Both hold strictly for
`s ∈ [0.05, 0.95]`, so the map is **strictly increasing analytically**, not just
empirically. `ReplayAthletePhaseMapTests` still verifies it on a dense
91 × 91 × 400 grid.

Both drive shares are clamped to `[0.05, 0.95]`, which keeps `Δdrive = d/s` and
`Δrecovery = (1−d)/(1−s)` finite and strictly positive — the precondition for
everything above.

### Degenerate identity

When `s == d` both secants are 1, `m = 3/((2−s) + (1+s)) = 1`, and
`H(u) = span·u`, i.e. the identity. The map only bends when the native and
authored drive shares actually disagree.

### Tolerances measured

| Check | Range | Tolerance | Worst measured |
| --- | --- | --- | --- |
| `f(0) = 0`, `f(s) = d` | 91 × 91 grid on `[0.05, 0.95]²` | 1e-12 | exact (landmark is a segment endpoint) |
| `f(1⁻) = 1` | production shares | 1e-8 at cycle `1 − 1e-9` | within tolerance |
| seam slope gap, `h = 1e-6` | driveFrac 0.28–0.46 × driveEnd {0.34, 0.38, 0.50} | 1e-5 | 9.3e-6 |
| wrap slope gap, `h = 1e-6` | same | 1e-5 | 9.3e-6 |
| seam/wrap slope gap, `h = 1e-6` | full `[0.05, 0.95]²` | 2e-3 | 1.14e-3 at the 0.95/0.05 corner |
| gap ratio `h → h/2` | production shares | 0.5 ± 0.05 | linear, as expected for an O(h) term |

The residual gap is the O(h) truncation term of the one-sided secant estimates,
not a discontinuity: halving `h` halves it. The previous linear map's gap was
constant in `h`.

### Behaviour changes called out individually

1. **`clipFraction` interpolation.** Same landmarks, Hermite instead of linear
   between them. This is the point of the slice.
2. **`isDrive` now clamps `authoredDriveEnd` the same way `clipFraction` does.**
   Previously `clipFraction` clamped to `[0.05, 0.95]` with a 0.5 fallback while
   `isDrive` compared against the raw value, so a non-finite `driveEnd` made
   `isDrive` always return false through a NaN comparison while `clipFraction`
   happily mapped against 0.5. The exit criterion requires the predicate to stay
   consistent with the map, so both now resolve the drive end through one
   `clampedDriveShare` helper. Authored values (0.38 / 0.34 / 0.50) are inside
   the clamp, so no production behaviour changes.

### Test assertion changed

One assertion in the pre-existing `testClipFractionUsesPhaseAndFiniteFallbacks`
changed: the fallback case (`phase = π`, `cycleFrac = NaN`, `driveFrac = ∞`,
`authoredDriveEnd = NaN`, resolving to cycle 0.5, `s = 0.4`, `d = 0.5`) returned
`7/12 ≈ 0.583333` under the linear map and returns `0.593343…` under the
Hermite one. The **fallback resolution itself is unchanged** — that is what the
test is named for — so the test now asserts the new value *and* asserts it
equals `clipFraction(cycle: 0.5, driveFrac: 0.4, driveEnd: 0.5)` computed
explicitly, which proves the fallbacks resolved to those values rather than the
literal being a coincidence. Every other assertion in both pre-existing tests is
unchanged and still passes.

### Not in this slice

No additive layer, no asset work, no renderer changes.

---

## 13B — Additive motion-graph pose layer

Status: planned; filled in on `phase-13b-additive-motion-layer`.

Core adds `ReplayAthleteAdditivePose`: pure, `Sendable`, Linux-testable. It maps
a `ReplayStrokePose` — through the existing `ReplayMotionGraph` sample, not a
second phase model — onto bounded local rotation offsets for the six semantic
bones the contact solver does not own.

Studio composes those offsets onto the sampled clip transform inside
`ReplayRigSource.apply(...)`, after `poseAdapter.apply(...)` and before
`ReplayAthleteContactSolver.solve(...)`, so the single existing solve pass
reconciles hands and feet against the modified torso.
`ReplayAthleteContactRole` is not widened.

Channel-to-bone assignment, per-bone angular limits, and their rationale are
recorded here when the slice lands.

---

## 13C — Per-stroke variation

Status: planned; filled in on `phase-13c-per-stroke-variation`.

A pure integer hash of `(ReplayStrokePose.index, sport)` drives bounded
asymmetry and timing jitter, so consecutive strokes are not bit-identical while
the same stroke index always reproduces exactly. Zero under Reduced Motion and
under `ROWPLAY_REPLAY_ACCEPTANCE=1`.

---

## 13D — Frame-pacing measurement

Status: planned; diagnostic only, no production rendering change.

Measure where Medium and Ultra frame time actually goes, using
`script/profile_replay.sh` against the staged bundle and the Phase 12 acceptance
harness. Record the dominant cost with numbers and the machine it was measured
on, and record explicitly what could not be measured. The fix is Phase 14 scope.
