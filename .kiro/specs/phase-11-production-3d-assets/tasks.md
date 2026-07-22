# Phase 11 - Production-Quality Bundled 3D Assets — Tasks

## Status Convention

Implementation and local validation are complete on PR #72. A checkbox is
marked only after the named implementation and its relevant validation are
complete. Exact-head GitHub CI is an external PR gate and is not implied by
these committed local checks.

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
- [x] Keep live and rival asset clones/materials independent and make every
  loaded ghost material translucent.
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
- [x] Inspect RowErg, SkiErg, and BikeErg at low, medium, high, and ultra;
  confirm low is procedural and valid higher tiers are bundled.
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
