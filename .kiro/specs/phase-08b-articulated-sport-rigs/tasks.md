# Phase 8B Tasks: Articulated Sport Rigs

## Spec
- [x] Create requirements.md
- [x] Create design.md
- [x] Create tasks.md

## Core Rig-Pose Model
- [x] Add `Sources/RowPlayCore/Replay/ReplayRigPose.swift` with value types and solver

## Studio Rig Files
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayMeshFactory.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayAthleteRig.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayRowerRig.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplaySkiErgRig.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayBikeErgRig.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplaySportRig.swift`

## Integration
- [x] Update `Replay3DSceneBuilder.swift` to use new rig system
- [x] Update `RealityReplaySceneView.swift` to compute and pass rig pose
- [x] Delete `ReplaySportModels.swift`

## Tests
- [x] Add `Tests/RowPlayCoreTests/Replay/ReplayRigPoseTests.swift`
- [x] Add `Tests/RowPlayStudioTests/ReplaySportRigStructureTests.swift`
- [x] Cover independent shoulders, ankle articulation, bike thigh bounds, and sport contact anchors

## Documentation
- [x] Update `docs/roadmap.md`
- [x] Update `docs/source-map.md`
- [x] Update `docs/beta-readiness.md`

## Validation
- [x] All test suites pass (803 Core tests and 27 Studio tests, 0 failures; 2 Core tests skipped)
- [x] Architecture checks pass (no forbidden imports in Core/Platform)
- [x] Build passes
- [x] Staged app bundle launches and remains running via `./script/build_and_run.sh --verify`
