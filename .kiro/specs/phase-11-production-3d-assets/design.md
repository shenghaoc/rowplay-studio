# Phase 11 — Current RowPlay Parity: Design

## Reference pipeline

`script/sync_rowplay_reference.py` reads artifacts from the exact pinned
RowPlay tree (`git show <commit>:<path>`), producing the `ReplayReference`
bundle: athlete USDZ + contract, the sampled motion table, the 13 CC0
texture families, and top-level manifests.  `script/convert_rowplay_equipment.py`
(Blender, dev-time) splits `rowplay-rigs-v3.glb` into three sport USDZ
packages with USD-safe prim names and sidecar contracts.
`script/export_rowplay_native_parity.mjs` evaluates the pinned web modules and
writes the parity fixtures.  `script/validate_rowplay_reference.py` is the
CI-safe committed-bundle gate.

## Athlete pipeline

- `ReplayAthleteCatalog` parses the live contract: semantic hierarchy,
  helper hierarchy with rest transforms, surfaces, clips, contacts, mesh
  stats, artifact hashes.  Nothing is hard-coded to 19 names.
- `ReplayAthleteMotionTable` (RowPlayCore) parses `rowplay-motion.bin` and
  interpolates all semantic bone locals per phase — O(bones), allocation-free
  sampling into a reusable buffer.
- `ReplayAthleteTemplate` validates the loaded USDZ skeleton against the
  contract (every bone resolved exactly once by leaf name, finite bind pose)
  and owns per-instance cloning.
- `ReplayAthleteInstance.seek(toClipFraction:)` writes semantic transforms
  from the table over a working pose whose helper joints were pre-composed
  once with the install-time grip closure; every seek is a fresh rebuild, so
  base-pose restore is structural, not procedural.
- `ReplayAthleteGripController` collects the ten digit chains from contract
  rest transforms, runs `ReplayHandClosure.solve` per hand with the sport
  contract, and caches the resulting helper rotations (rest × oppose ×
  flex, plus the palm-cup roll on `v4*Fingers`).
- Rival styling is an opaque cool tint (white → ghost teal 34 %); live gets
  the 14 % violet identity tint.  No alpha on the deforming body.

## Grip system (RowPlayCore)

`ReplayGripGeometry` owns the measured hand-channel model (curl axis, fist
centre/radius, palm contact/normals, seat flesh, palm cup) and grip-frame
orientation (`orientHandToGripChannel`, wrist spin/tilt refinements).
`ReplayHandClosure` is the deterministic digit-closure solver: 24-sample
sweeps + 28-iteration bisection per stage, thumb radial/end-press modes, and
the opt-in 16³ wrapped enclosure used by the BikeErg hoods.  Sport contracts
supply surfaces and options and also carry the full equipment dimension
tables (`ReplayRowGripContract`, `ReplaySkiGripContract`,
`ReplayBikeGripContract` + `ReplayBikeSaddle`).

## Scene composition

`Replay3DSceneBuilder` composes: native venue (`ReplayEnvironment*` from the
ported plan + CC0 maps, per-tier), sport rig (procedural from Core contracts
at Low/Medium, authored packages at High/Ultra via
`ReplayBundledRigVisualProvider`), production athletes (live + rival), the
effect renderer, and the per-sport chase camera
(`ReplayCameraSolver`/`ReplayCameraChaseRig` in Core).  2D scenes live in
`Views/Replay2D/` and consume the same motion graph.

## Failure model

Athlete, equipment and venue loads validate atomically and cache failures;
any gate failure yields the complete procedural scene with all replay state
(time, play/pause, speed, camera, quality, rival) preserved.  No per-frame
retries, no mixed scenes.
