# Phase 11 — Current RowPlay Parity: Design

## Reference pipeline

`script/sync_rowplay_reference.py` reads artifacts from the exact pinned
RowPlay tree (`git show <commit>:<path>`), producing the `ReplayReference`
bundle: athlete USDZ + contract, the sampled motion table, the 13 CC0
texture families, and top-level manifests.  `script/convert_rowplay_equipment.py`
(Blender, dev-time) splits `rowplay-rigs-v3.glb` into three sport USDZ
packages with USD-safe prim names and sidecar contracts.
`script/convert_rowplay_athlete.py` (Blender/OpenUSD, dev-time) retains the
pinned athlete USDZ's geometry, skinning, contacts, and animation while using
the pinned GLB vertex colours to author eight deterministic material subsets.
Its native manifest seals both inputs, the triangle-role counts, and the
byte-stable output; it is a material-binding derivative, not a remodel or
replacement rig.
`script/export_rowplay_native_parity.mjs` evaluates the pinned web modules and
writes the parity fixtures.  `script/validate_rowplay_reference.py` is the
CI-safe committed-bundle gate.

## Athlete pipeline

- `ReplayAthleteCatalog` parses the live contract: semantic hierarchy,
  helper hierarchy with rest transforms, surfaces, clips, contacts, mesh
  stats, artifact hashes, and the native derivative manifest. Nothing is
  hard-coded to 19 names; native activation requires exactly one skinned mesh
  and all eight ordered runtime material bindings.
- `ReplayAthleteLibrary` resolves bundle URLs on `MainActor`, then performs
  portable reads, SHA-256, JSON parsing, and motion-table validation in a
  detached task. RealityKit entity loading and cache installation are the only
  cold-load work kept on `MainActor`.
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
  flex, plus palm-cup roll resolved through the contract-derived hand helper
  mapping rather than a hard-coded joint name).
- Rival styling is an opaque cool tint (white → ghost teal 34 %); live gets
  the 14 % violet identity tint. Each clone owns its eight PBR material values
  and skeleton state. No alpha on the deforming body.
- `ReplayAthleteMaterialLibrary` owns the pinned per-role PBR ladder and
  process-shared deterministic normal-detail resources. Low allocates no
  detail map; Medium/High/Ultra generate exact 128/256/512 px maps off-main,
  then create and cache immutable RealityKit texture resources once per tier
  for reuse by live and rival instances. No network request is possible.
- Each sport rig fixes a `ReplayRigSource` at build time. Bundled rigs require
  a motion sample and use one shared sample/contact pipeline; they never fall
  through to an unbuilt procedural athlete during pose application.
- Contact roles and terminal bones come from the validated athlete contract.
  One precomputed hierarchy/contact plan and one mutable matrix workspace are
  reused per instance; joint edits update only dirty descendant matrices and
  a failed residual restores the sampled pose atomically.

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

`Replay3DSceneBuilder` composes: a non-failable native procedural venue
(`ReplayEnvironment*` live plan + per-tier primary-receiver CC0 maps), sport
equipment (procedural from Core contracts at Low/Medium, authored packages at
High/Ultra via `ReplayBundledRigVisualProvider`), and production athletes —
independent live and rival V4 clones with their own materials and skeletons, at
every tier once the asset set validates.  Athlete surface detail follows the
0/128/256/512 px Low/Medium/High/Ultra ladder independently of the
equipment-source split.
The builder also owns the effect renderer and per-sport chase camera
(`ReplayCameraSolver`/`ReplayCameraChaseRig` in Core).  2D scenes live in
`Views/Replay2D/` and consume the same motion graph.

## Failure model

Athlete and equipment packages validate atomically and cache failures. A
missing or invalid complete asset set yields the complete procedural rig with
replay state (time, play/pause, speed, camera, quality, rival) preserved.
Low/Medium's validated V4 athlete plus procedural equipment is the intended
tier policy, not a failure hybrid. When High/Ultra requests authored equipment,
every logical visual clone is preflighted before either authored athlete or
equipment is attached; a preflight failure discards both, so athlete/equipment
fallbacks never form mixed scenes. A canonical-athlete runtime failure at any
tier drops the asset set and rebuilds the complete procedural scene without
per-frame retries.

Native venue geometry is deterministic and non-failable. Missing environment
texture slots are cached and degrade only that primary receiver to its scalar
PBR values; no per-frame retries occur.

Equipment bundle URL resolution and RealityKit entity/provider work stay on
the main actor; immutable manifest/package reads, streaming hashes, JSON
parsing and contract validation run on detached work before the entity load.
The process-shared library coalesces both manifest and per-sport requests so
responsiveness does not create duplicate validation.
