# Phase 8A Design: RealityKit 3D Replay Foundation

## Architecture

```
RowPlayCore (no platform imports)
├── Replay/ReplayStrokePose.swift     ← pure pose model, ported from strokeModel.ts
├── Replay/ReplayCourseLayout.swift   ← pure 400m loop layout
└── Fixtures/stroke-pose-parity.json  ← web parity fixture

RowPlayStudio (RealityKit, SwiftUI)
├── Views/Replay3D/ReplayRendererMode.swift       ← .twoD / .threeD enum
├── Views/Replay3D/RealityReplaySceneView.swift    ← RealityView wrapper
├── Views/Replay3D/Replay3DSceneBuilder.swift      ← entity graph, course, lighting
├── Views/Replay3D/ReplaySportModels.swift         ← procedural sport placeholders
└── Views/ReplayView.swift                          ← updated with 2D/3D picker
```

Dependency direction: `RowPlayStudio → RowPlayPlatform → RowPlayCore`. RealityKit and all 3D entities live only in `RowPlayStudio`.

## ReplayStrokePose (Core)

Ported from web `src/lib/replay/strokeModel.ts`. Pure data-derived pose model:

- `ReplayStrokePoseContext` bundles sport, peak watts, median watts, median DPS, and max HR — the aggregates that `strokePoseAt` uses for normalization.
- `compute(frame:context:)` mirrors `strokePoseAt()` exactly: watts normalization (55%), DPS normalization (30%), rate normalization (15%), HR-based fatigue, progress-based fatigue, amplitude from intensity+fatigue.
- `fallback(sport:phase:rate:)` mirrors `fallbackStrokePose()` for workouts without stroke data.
- All inputs are sanitized for non-finite values before computation.

## ReplayCourseLayout (Core)

A 400-metre circular loop (matching a standard rowing track):

- `loopRadius` = 12.73m (gives circumference ≈ 80m per lane at center; the 400m is the center-line distance).
- `position(at:lane:)` returns `(x, y, z)` on the loop with lane offset.
- `tangent(at:)` returns the unit direction of travel.
- `headingAngle(at:)` returns the Y rotation for entity orientation.
- Multiple laps wrap naturally via modular arithmetic.

## RealityKit Scene (Studio)

### Entity Lifecycle

1. `RealityView { make in ... }` creates the full entity graph once: course ground, lane rings, start/finish line, lighting, camera, live entity group, ghost entity group.
2. `RealityView.update { ... }` receives the current `ReplayState` and `ReplayStrokePose`, then updates:
   - Entity positions along the course via `ReplayCourseLayout`.
   - Entity orientations via heading angle.
   - Articulated motion (oar sweep, pole swing, pedal rotation) from pose phase.
   - Ghost visibility and translucency.
   - Camera position (chase cam).

### Course

- Flat ground plane with sport-appropriate color (water blue for rower, snow white for SkiErg, asphalt grey for BikeErg).
- Lane ring (torus) marking the course path.
- Start/finish checkerboard marker.
- Directional sunlight + ambient fill.

### Sport Placeholders

Low-poly procedural meshes built from `MeshResource` primitives:

- **RowErg**: elongated capsule hull, thin rail, seat block, handle cylinder, seated athlete (torso ellipsoid, head sphere, arm cylinders, leg cylinders). Oar groups animate with `warpedPhase`.
- **SkiErg**: vertical frame posts, cable/handle, platform block, standing athlete. Poles animate with `warpedPhase`.
- **BikeErg**: diamond frame (boxes), two torus wheels, crank disc, pedals, seated athlete. Wheels and cranks animate with `phase`.

### Camera

- Fixed chase camera: positioned behind and above the live entity, looking ahead along the tangent.
- Smooth interpolation using `dampFactor` from `ReplayMotion` (frame-rate independent).
- Under reduced motion: camera snaps to position without smoothing.
- Camera never produces non-finite transforms (all positions are bounded by the loop geometry).

### Reduced Motion

- Freeze body articulation (oars, poles, pedals) at neutral pose.
- Disable camera smoothing and bob.
- Still allow position updates from scrubbing/progress.

### Accessibility

- One `.accessibilityElement(children: .ignore)` on the 3D surface.
- Label: "3D workout replay".
- Value: "{Sport} · {progress}% · {pace} · {cadence} {unit} · ghost {present/absent}".

## ReplayView Integration

- `@State private var rendererMode: ReplayRendererMode = .threeD` in `ReplayView`.
- `Picker("Renderer", ...)` with `.segmented` style above the replay surface.
- `switch rendererMode { case .twoD: existingCanvas; case .threeD: RealityReplaySceneView(...) }`.
- Telemetry bar, playback controls, scrubber, speed picker remain outside the switch — shared by both modes.
- Minimum height of 300pt for both modes (matching existing canvas).
- If RealityKit setup fails, `RealityReplaySceneView` shows an error state and the picker still allows switching to 2D.

## Test Strategy

- `ReplayStrokePoseTests`: verify all fields match web `strokePoseAt` output for representative inputs across three sports, reduced motion frozen output, fallback cadence, fatigue/amplitude bounds, and non-finite input sanitization.
- `ReplayCourseLayoutTests`: verify position wrapping at lap boundaries, multiple laps, lane offsets produce correct lateral displacement, tangent is unit length, heading angle is finite, negative distance produces finite position, non-finite inputs produce fallback.
- `ReplayRendererModeTests`: verify labels, default value, and case count.
- Regression: existing `ReplayStateTests` and `ReplayMotionTests` must pass unchanged.
