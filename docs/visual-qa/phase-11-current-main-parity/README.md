# Phase 11 — Current-Main Parity: Visual QA

This folder records the truthful visual state of the native replay against
the pinned current RowPlay `main` build (commit recorded in
`Sources/RowPlayStudio/Resources/ReplayReference/rowplay-source.json`).

## Baseline (pre-change PR #72 state)

Captured by code inspection and the full test suite at the rebased PR #72
head (commit `19e4538`), before this parity pass:

- **Production athlete did not load.**  `ReplayAthleteTemplate` required all
  three contract clip names among `Entity.availableAnimations`; the merged
  USDZ does not preserve them, so the loader intentionally selected the
  complete procedural fallback at every tier (this was documented in-code
  and in `docs/beta-readiness.md`).
- **2D replay was not a sport scene.**  `Replay2DSceneView` rendered a
  time/distance strip with progress dots — no course, no equipment, no
  articulated participant.
- **Equipment was the pre-parity concept set**: RowErg kept a central
  indoor-rower handle; SkiErg was a machine (tower/cable/platform) rather
  than a course skier; BikeErg was a stylized frame, not the true-scale
  road bicycle.
- **Environments were the sparse six-USDA package** (per-sport ring and
  simple props), Medium+ only, with the procedural ground below.
- **Quality tiers**: Low forced procedural; Medium/High/Ultra differed only
  in counts and the USDA package — with the athlete gate failing, all tiers
  rendered the procedural mannequin.
- Baseline gates run: `swift test` (pass), `swift build` (pass).
- **Honest gap**: no screenshot captures of the pre-change app were archived
  before the parity work began; the baseline above is from source inspection
  and the recorded loader behavior, not from saved frames.

## Current-state capture matrix

See `capture-notes.md` (written after the parity implementation) for the
matrix actually performed against `dist/RowPlayStudio.app` and what remains
unavailable in this environment.
