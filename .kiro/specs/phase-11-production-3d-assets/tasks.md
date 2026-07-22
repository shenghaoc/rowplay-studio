> **Canonical merged-source amendment (2026-07-22):** The source is merged
> RowPlay PR #171 commit `da0dc73bf295871e9b362511cd5b2c9a9424b325`, pinned
> with final GLB/USDZ/contract hashes in the source manifest. The exact USDZ
> lacks the three contract-named clips, so this branch intentionally rejects
> it as a whole and stays draft. A local alias or first-animation fallback is
> prohibited; the remaining unchecked V4 visual gate requires an upstream
> artifact/contract correction.

# Phase 11 - Production-Quality Bundled 3D Assets — Tasks

## Status Convention

The original checked list records the completed native equipment/environment
foundation. The canonical V4 continuation below is authoritative for this PR's
current readiness. Exact-head GitHub CI remains an external PR gate and is not
implied by local checks.

## Canonical Merged V4 Continuation

- [x] Pin sync to merged commit `da0dc73bf295871e9b362511cd5b2c9a9424b325`,
  exact Git-tree reads, reachability verification, final hashes, manifest
  `merged` status, and `--check` mode.
- [x] Make the manifest the runtime authority for pin/hash validation rather
  than duplicating production constants in the loader.
- [x] Port the V4 motion graph, sport kinematics, and two-bone solver into
  RowPlayCore; generate and test the 129-phase-per-sport parity corpus.
- [x] Replace marker snapping with deterministic skeletal correction in
  `prepare -> orientHandsToTargets -> constrain` order.
- [x] Require one exact named animation resource for each sport; make load and
  runtime failures rebuild the complete procedural scene without state loss.
- [x] Keep V4 rival bodies opaque/depth-writing with a cool tint while keeping
  rival equipment translucent.
- [x] Add regression coverage for the actual merged asset/contract mismatch
  and complete procedural fallback at all quality tiers.
- [ ] **Blocked upstream:** load and visually validate all three exact
  contract-named V4 clips (RowErg, SkiErg, BikeErg) in the staged app. The
  current final USDZ contains only `rowplay_v4_row_cycle`.

## Spec and Documentation

- [x] Create Phase 11 requirements, design, and task documents as one phase.
- [x] Add `docs/replay-assets.md` as the asset contract and maintenance guide.
- [x] Update roadmap, source map, and beta-readiness with the actual local
  validation evidence and explicit unavailable checks.

## Deterministic Asset Pipeline

- [x] Add `script/generate_replay_assets.py` using only the Python standard
  library and deterministic ordering.
- [x] Generate the three sport rig USDA files.
- [x] Generate the three sport environment USDA files.
- [x] Add `--check` drift and contract validation without a write side effect.
- [x] Add `ASSET_PROVENANCE.md` with original-project provenance and exact
  regeneration command.
- [x] Enforce triangle, aggregate-size, finite geometry, required-node, and
  no-camera/no-light budgets.
- [x] Register the generated resources in the SwiftPM Studio target.

## Asset Contract and Loading

- [x] Add `ReplayAssetCatalog.swift` as the source of truth for resources,
  node contracts, material categories, bounds, budgets, and selection rules.
- [x] Add `ReplayAssetLibrary.swift` with `Bundle.module` loading, all-or-
  nothing validation, bounded template caching, independent clone creation,
  and injectable failure testing.
- [x] Add `Tests/RowPlayStudioTests/Fixtures/replay-asset-contract.json`.
- [x] Add `ReplayAssetCatalogTests.swift` for the deterministic catalog and
  quality/fallback contract.
- [x] Add `ReplayAssetLibraryTests.swift` for resource validation, cloning, and
  missing/malformed/incomplete failure paths.

## Visual Providers and Sport Rigs

- [x] Add `ReplayRigVisualProvider.swift`.
- [x] Preserve existing generated mesh attachment as the complete procedural
  source selected by `ReplayProceduralRigVisualProvider` without changing
  low-quality behavior.
- [x] Add `ReplayBundledRigVisualProvider.swift` that maps validated visual
  nodes onto existing logical pivots without duplicating pose application.
- [x] Preserve named pivots, finite-transform guards, and contact invariants in
  `ReplayAthleteRig` and all sport rig classes.
- [x] Keep live and rival asset clones/materials independent; make ghost
  equipment translucent while keeping a validated V4 rival body opaque and
  cool-tinted.
- [x] Add `ReplayBundledSportRigTests.swift` for low/bundled rig structure,
  moving sport equipment, contacts, clone isolation, and non-finite safety.

## Environment and Scene Integration

- [x] Add `ReplayEnvironmentAssetInstaller.swift`.
- [x] Install bundled sport environment only for a valid medium/high/ultra
  sport set and preserve the procedural low path.
- [x] Retain native 400-metre layout, lanes, markers, lights, cameras, wakes,
  and catch effects.
- [x] Switch quality graph visuals without resetting replay time, speed,
  camera/orbit state, or rival selection.
- [x] Add `ReplayEnvironmentAssetTests.swift` for resource/environment
  contract, bundled-only installation, and fallback behavior.
- [x] Extend existing scene, quality, effect, ghost, and rig tests without
  weakening their established behavior.

## Focused Validation

- [x] `python3 script/generate_replay_assets.py --check`
- [x] `swift test --filter ReplayAssetCatalogTests`
- [x] `swift test --filter ReplayAssetLibraryTests`
- [x] `swift test --filter ReplayBundledSportRigTests`
- [x] `swift test --filter ReplayEnvironmentAssetTests`
- [x] `swift test --filter ReplaySportRigStructureTests`
- [x] `swift test --filter Replay3DSceneEffectsTests`
- [x] `swift test --filter ReplayQualitySceneTests`
- [x] `swift test --filter ReplayGhostWorkflowTests`
- [x] Core forbidden-import scan returns no matches.
- [x] Platform forbidden-UI-import scan returns no matches.

## Complete Validation and Staged-App QA

- [x] `swift test`
- [x] `swift build`
- [x] `git diff --check`
- [x] `./script/build_and_run.sh --verify`
- [x] `./script/build_and_run.sh --automation`
- [x] `./script/build_and_run.sh --sign-verify`
- [x] Confirm the staged bundle contains all six generated USDA resources.
- [ ] **Blocked upstream:** inspect a validating V4 RowErg, SkiErg, and BikeErg
  at medium, high, and ultra. The current exact USDZ fails the required clip
  gate, so all current tiers correctly render the complete procedural fallback.
- [x] Exercise pause/resume, seek, Low-to-Medium state preservation, and
  automation mode in the staged app.
- [x] Inspect the live participant, past-session and constant-pace rivals, all
  cameras, light/dark appearance, Reduced Motion, and the largest/compact
  windows available in the current environment.
- [x] Open a real imported-rival CSV in the native panel and verify the current
  bounded importer plus imported-rival 3D fallback with focused tests. Record
  that the desktop QA bridge could not perform the final panel selection in
  this run instead of claiming a current imported-rival screenshot.
- [x] Record only actually captured screenshots, observations, and unavailable
  VoiceOver, pointer-gesture, imported-panel-selection, Instruments, or GPU
  proof.

## Final Audit

- [x] Audit generated provenance, deterministic output, resource budgets,
  atomic fallback, material isolation, contact preservation, and no per-frame
  resource work.
- [x] Audit architecture imports, privacy-safe diagnostics, no third-party
  assets, no debug output, no conflict markers, and no unrelated changes.
- [x] Update PR #72 with actual validation evidence only after the preceding
  gates pass.
