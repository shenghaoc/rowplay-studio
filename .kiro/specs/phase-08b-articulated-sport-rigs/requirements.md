# Phase 8B Requirements: Articulated Sport Rigs

## Overview

Upgrade the Phase 8A placeholder RealityKit avatars to high-fidelity articulated sport rigs with proper joint hierarchies, anatomical pivots, contact invariants, and deterministic pose application.

## Requirements

### R1: Core Rig-Pose Model
- `ReplayRigPose.swift` in `RowPlayCore/Replay/` with portable, deterministic rig-pose value types.
- `ReplayAthleteJointPose` for common torso/head/shoulder/elbow/hip/knee/ankle targets.
- Sport-specific pose types: `RowerRigPose`, `SkiErgRigPose`, `BikeErgRigPose`.
- `ReplaySportRigPose` enum with `.rower`, `.skierg`, `.bike` cases.
- `ReplayRigPoseSolver.solve(sport:strokePose:distance:reduceMotion:)` pure function.
- All types `Equatable` and `Sendable`. No platform imports.

### R2: Articulated Entity Hierarchy
- Named pivot chain: pelvis → torso → shoulders → upper arms → forearms → hands; pelvis → thighs → shins → feet.
- Joints rotate around anatomical pivots, not arbitrary world-position offsets.
- Stylized low-poly geometry with coherent proportions (tapered limbs, hands, feet, head).
- Materials follow the merged design-system palette.
- Ghost translucency applied recursively to every rig material.

### R3: Contact Invariants
- RowErg: hands on handle, feet at footplate, pelvis on seat, oars pivot from gates.
- SkiErg: hands on handles, cable/pole endpoints follow handles, feet on platform.
- BikeErg: hands on handlebar, pelvis on saddle, each foot on its pedal.
- Contact errors must not accumulate. Scrubbing to same timestamp produces same transforms.

### R4: Animation Integration
- Compute `ReplaySportRigPose` from `ReplayStrokePose` during scene updates.
- Replace Phase 8A placeholder animation with deterministic rig-pose application.
- Preserve `ReplayState` as only playback clock. No new timers.
- Preserve course placement, ghost lane, chase camera, 2D/3D selector, telemetry, controls.
- Do not rebuild entity graph on scrub/speed change.
- Sport/workout changes recreate correct rig exactly once.

### R5: File Organization
- Split `ReplaySportModels.swift` into focused files.
- Keep small dispatch/factory surface; no god file.
- Every rig and builder `@MainActor`.
- Create meshes/materials once. Frame updates change transforms only.
- Share immutable `MeshResource` values between live and ghost rigs where safe.
- No global mutable caches or `@unchecked Sendable`.

### R6: Tests
- Core `ReplayRigPoseTests`: catch/mid-drive/finish/recovery for rower; tall/compressed for skierg; 0°/90°/180°/270° for bike; reduced motion; NaN/infinity/negative inputs; determinism.
- Studio `ReplaySportRigStructureTests`: named joints exist, nonempty geometry, separate live/ghost hierarchies, ghost translucency, pose application, no drift, finite transforms.
- All Phase 8A tests remain green.

### R7: Documentation
- Update `docs/roadmap.md`, `docs/source-map.md`, `docs/beta-readiness.md`.
- Document Phase 8C/8D gaps.

## Non-Goals

No USD/USDZ assets, character skinning, IK engine, facial animation, camera selector, orbit camera, particles, wakes, water simulation, adaptive quality, Metal shaders, SceneKit, Bluetooth.
