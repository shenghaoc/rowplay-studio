# Phase 11 - Production-Quality Bundled 3D Assets — Requirements

## Overview

Phase 11 upgrades the native RealityKit replay presentation from wholly procedural
placeholder visuals to bundled, deterministic, project-authored 3D assets for
RowErg, SkiErg, and BikeErg. It preserves the existing native replay clock,
`ReplayRigPoseSolver`, logical pivot hierarchy, contact invariants, cameras,
effects, quality policy, rival workflow, 2D renderer, demo mode, and
automation mode.

This is a native-owned visual-provider phase. It does not create a second
renderer, skeletal animation system, network asset service, or web dependency.
The procedural rigs and environments remain the complete, reliable fallback.

## R1: Architecture and Scope Boundaries

- **R1.1** Dependency direction remains `RowPlayStudio -> RowPlayPlatform ->
  RowPlayCore`.
- **R1.2** USDA generation, resource loading, RealityKit entities, materials,
  and environment installation belong in `RowPlayStudio` only.
- **R1.3** `RowPlayCore` keeps the portable replay timing, course layout,
  stroke pose, rig pose, contact targets, quality policy, and performance
  policy. Phase 11 does not add UI, RealityKit, AppKit, Combine, Security, or
  Charts imports to Core.
- **R1.4** The current logical sport rigs continue to own named pivots,
  `applyPose`, contact anchors, and finite-transform guards. A visual provider
  supplies geometry to those pivots; it does not replace the pose solver.
- **R1.5** The phase adds no external package, runtime download, toolchain,
  deployment-target, CI-runner, product, target-graph, replay-control, or 2D
  renderer change.

## R2: Deterministic Bundled Asset Pipeline

- **R2.1** `script/generate_replay_assets.py` uses only the Python standard
  library, fixed ordering, and fixed deterministic inputs. It makes no network
  request and has no download path.
- **R2.2** The generator writes readable ASCII USDA resources under
  `Sources/RowPlayStudio/Resources/Replay3D/`:

  - `rower-rig.usda`
  - `skierg-rig.usda`
  - `bike-rig.usda`
  - `rower-environment.usda`
  - `skierg-environment.usda`
  - `bike-environment.usda`

- **R2.3** Running `python3 script/generate_replay_assets.py --check` must
  reject stale generated output and contract violations without rewriting
  committed resources.
- **R2.4** `ASSET_PROVENANCE.md` records that the files are original
  project-generated work, their source inputs, and the exact regeneration
  command. No third-party model, logo, trademark, scan, likeness, or ambiguous
  redistribution licence may be introduced.
- **R2.5** Assets are packaged as SwiftPM resources and load only from
  `Bundle.module` at runtime.
- **R2.6** No rig asset exceeds 18,000 triangles, no environment asset exceeds
  30,000 triangles, and the six generated assets together remain below 15 MiB.
- **R2.7** All generated geometry is non-empty and has finite transforms and
  normals. Required node names are unique. Assets contain no camera or light;
  native camera and lighting remain authoritative.

## R3: Visual Direction

- **R3.1** Athlete assets use a cohesive, non-photorealistic silhouette with
  tapered/rounded anatomy, readable head and hair, kit, hands, shoes, and
  smooth joint transitions rather than visibly assembled primitives.
- **R3.2** Equipment has sport-recognisable silhouettes and moving parts:
  hull/seat/handle/oars for RowErg; frame/handles/poles/cable for SkiErg; and
  frame/wheels/cranks/pedals/handlebar for BikeErg.
- **R3.3** Materials use a restrained palette with base, accent, metal, trim,
  and environment categories. Surface treatment conveys base colour,
  roughness, and metallic distinction without custom shaders.
- **R3.4** Environments add depth without taking over course semantics:
  RowErg has water, shoreline, buoys, dock, and restrained vegetation; SkiErg
  has snow, conifers, gates, and snowbanks; BikeErg has a paved or velodrome
  course, barriers, banners, and trackside depth.
- **R3.5** Assets contain no branding or trademark-like marks. Their scale,
  orientation, pivots, and art direction remain coherent across all sports.

## R4: Asset Contract

- **R4.1** `ReplayAssetCatalog` is the single source of truth for resource
  names, kind, sport association, required nodes, material categories, bounds,
  and budgets. The golden `replay-asset-contract.json` records the same
  deterministic contract for tests.
- **R4.2** Every rig declares these common visual nodes:

  ```text
  visual-pelvis, visual-torso, visual-head,
  visual-upperArm-L, visual-forearm-L, visual-hand-L,
  visual-upperArm-R, visual-forearm-R, visual-hand-R,
  visual-thigh-L, visual-shin-L, visual-foot-L,
  visual-thigh-R, visual-shin-R, visual-foot-R
  ```

- **R4.3** The RowErg rig additionally declares `visual-hull`,
  `visual-deck-stripe`, `visual-footplate`, `visual-rail`, `visual-seat`,
  `visual-handle`, `visual-oar-port`, and `visual-oar-starboard`.
- **R4.4** The SkiErg rig additionally declares `visual-post-L`,
  `visual-post-R`, `visual-topBar`, `visual-platform`, `visual-handle-L`,
  `visual-handle-R`, `visual-pole-L`, `visual-pole-R`, and `visual-cable`.
- **R4.5** The BikeErg rig additionally declares `visual-wheel-front`,
  `visual-wheel-rear`, `visual-downTube`, `visual-seatTube`,
  `visual-topTube`, `visual-cranks`, `visual-chainRing`, `visual-pedal-L`,
  `visual-pedal-R`, `visual-handlebar`, and `visual-saddle`.
- **R4.6** Every environment declares `environment-root`,
  `environment-ground`, and `environment-props`.

## R5: Providers, Quality, and Fallback

- **R5.1** Geometry selection is isolated behind `ReplayRigVisualProvider`.
  `ReplayProceduralRigVisualProvider` retains the existing generated geometry;
  `ReplayBundledRigVisualProvider` attaches validated asset geometry to the
  same logical pivots.
- **R5.2** `ReplayAssetLibrary` loads and validates templates once per process,
  provides independent recursive clones for live and rival rigs, supports an
  injectable resource source for failure tests, and never loads or traverses
  assets in a per-frame update.
- **R5.3** `.low` quality always uses the existing procedural rig and generic
  procedural environment. `.medium`, `.high`, and `.ultra` use bundled visuals
  only when that sport's complete asset set validates.
- **R5.4** Missing, malformed, incomplete, or incompatible assets select the
  complete procedural sport rig and environment. A scene must never combine
  some bundled body/equipment/environment parts with procedural substitutes.
- **R5.5** A quality graph rebuild switches visual sources without resetting
  replay time, play/pause state, speed, camera preset, orbit state, or rival
  selection. It retains existing quality governor semantics.
- **R5.6** `ReplayEnvironmentAssetInstaller` installs the sport-specific
  environment at medium quality or above and suppresses only the generic
  background it replaces. The native 400-metre layout, lanes, markers, start /
  finish line, camera, lights, wakes, and catch effects remain native-owned.

## R6: Rigs, Rivals, Reduced Motion, and Accessibility

- **R6.1** Existing articulation and contact invariants remain authoritative:
  RowErg hands/feet/pelvis/oars, SkiErg hands/feet/poles/cable, and BikeErg
  hands/feet/pelvis/pedals/cranks retain their current targets.
- **R6.2** Live and rival rigs receive independent asset clones. Changing a
  rival material must not mutate the live rig, a cached template, or another
  scene.
- **R6.3** Ghost translucency applies to every material type loaded from USDA,
  including PBR-style materials, while preserving sport accents on the live
  participant.
- **R6.4** Imported and constant-pace rivals retain their existing fallback
  articulation. Reduced Motion retains stable neutral poses, and existing wake
  and spray suppression rules remain in force.
- **R6.5** The 3D surface remains a single meaningful accessibility element.
  Decorative asset node names are hidden from VoiceOver, no new visual-source
  control is exposed, and existing keyboard controls remain operable.

## R7: Tests and Validation

- **R7.1** Asset tests cover resource presence in `Bundle.module`, USDA loading,
  required nodes, material categories, finite transforms/normals/bounds,
  triangle and size budgets, absence of cameras/lights, clone independence,
  and generator `--check`.
- **R7.2** Failure tests prove missing, malformed, and incomplete resource sets
  produce an operational complete procedural fallback.
- **R7.3** Rig tests run existing structural, finite-transform, contact, and
  ghost-translucency assertions against procedural low-quality and bundled
  medium-quality paths. They retain all named pivots and sport moving parts.
- **R7.4** Scene tests cover low/procedural versus medium-high-ultra/bundled
  selection, environment installation, quality rebuild continuity, effects,
  cameras, rivals, seeking, Reduced Motion, and functional load failure.
- **R7.5** Required validation includes the generator check, focused asset and
  replay suites, Core/Platform architecture scans, full `swift test`, `swift
  build`, `git diff --check`, staged-bundle checks, and staged-app visual QA.
  A task is complete only when its corresponding proof has actually passed.

## R8: Privacy and Performance

- **R8.1** Assets contain no user data. Asset errors/logs never disclose tokens,
  workout data, file paths, filenames, or other private values. Any fallback
  log uses only a fixed public resource identifier and is emitted at most once
  per failed resource.
- **R8.2** Templates load only during scene construction and use a bounded
  cache. Per-frame work changes existing transforms/material state only; it
  performs no disk I/O, asset traversal, mesh generation, or unbounded
  allocation.
- **R8.3** Phase 11 preserves existing adaptive-quality measurements. It does
  not claim a performance improvement, universal frame rate, or final
  production readiness without measured evidence.
- **R8.4** Demo and automation modes remain deterministic and offline.

## Non-Goals

- A new animation, skeletal, inverse-kinematics, or renderer system.
- Metal, SceneKit, custom shaders, runtime downloads, external model loaders,
  third-party assets, asset marketplace, or user-selectable visual themes.
- New replay controls, a 2D redesign, networking, Bluetooth/FTMS/Concept2 PM
  transport, OAuth, public sharing, or unrelated UI cleanup.
