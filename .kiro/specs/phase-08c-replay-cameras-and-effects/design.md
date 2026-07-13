# Phase 8C Design: Replay Cameras and Sport Effects

## Architecture

```
RowPlayCore/Replay/
├── ReplayCamera.swift
│   ├── ReplayCameraPreset / ReplayCameraOrbit / ReplayCameraPose
│   └── ReplayCameraSolver
└── ReplayEffects.swift
    ├── ReplayEffectProfile / ReplayEffectPoint / ReplayParticle
    ├── ReplayParticlePool / ReplaySprayGenerator
    └── ReplayWakeEntry / ReplayWakeHistory

RowPlayStudio/Views/Replay3D/
├── ReplayCameraController.swift
├── ReplayEffectRenderer.swift
├── RealityReplaySceneView.swift
└── Replay3DSceneBuilder.swift

RowPlayStudio/Views/ReplayView.swift
└── owns preset selection and camera-reset generation
```

Dependency direction remains `RowPlayStudio → RowPlayPlatform → RowPlayCore`. Core contains no SIMD or UI/renderer types. Studio performs the final conversion from finite Core scalar values to RealityKit `SIMD3<Float>` values.

## Camera Core Model

`ReplayCameraPreset` is a `String`, `CaseIterable`, `Sendable`, `Equatable` enum with `chase`, `side`, `overhead`, and `orbit`. Display labels and SF Symbols remain portable string metadata so the SwiftUI Picker can render without duplicating names.

`ReplayCameraOrbit` stores yaw, pitch, and distance as `Double` values. Its initializer and adjustment methods sanitize and clamp every update:

- yaw normalized to `-π...π`;
- pitch clamped to `10°...75°`;
- distance clamped to `4...30` metres;
- default orbit: yaw `0`, pitch `28°`, distance `10` metres.

`ReplayCameraPose` stores `positionX/Y/Z`, `targetX/Y/Z`, and `fieldOfViewDegrees`. It provides a finite check and deterministic fallback.

`ReplayCameraSolver.targetPose(...)` first sanitizes participant coordinates, normalizes the horizontal course tangent, and derives a horizontal right vector. A degenerate tangent falls back to `(1, 0, 0)`.

- **Chase**: `5.8m` behind, `3.6m` high, `1.1m` outward, looking `4.4m` ahead at `0.85m` height.
- **Side**: `9m` to the tangent's right and `2.8m` high, looking at the participant at `0.9m` height.
- **Overhead**: `18m` above and `2m` behind, looking at the participant at `0.5m` height. The small trailing offset keeps equipment orientation readable and prevents a degenerate straight-down view.
- **Orbit**: spherical offset from the participant using clamped orbit yaw, pitch, and distance, with yaw zero aligned behind the course tangent.

Chase FOV is `46 + clamp((speed - 3) / 6, 0...1) * 5`; all other presets use 46 degrees. Non-finite or negative speed becomes zero. Reduced motion forces 46 degrees for every preset.

`ReplayCameraSolver.smoothedPose(...)` uses `ReplayMotion.dampFactor(rate:dt:)` for position/look-target convergence and a separate bounded FOV rate. A non-finite current pose, reduced motion, preset/reset change, seek, or paused seek returns the target directly. A zero-movement pause preserves the current pose and FOV. This makes equal wall-clock intervals converge identically at 30, 60, and 120 Hz.

## Camera Studio Controller

`ReplayCameraController` owns only scene-local camera mechanics: clamped orbit state, current solved pose, smoothed replay speed, previous distance, last preset, drag baseline, and magnification baseline. It does not own playback time.

Each scene update:

1. derives finite participant/tangent values from `ReplayCourseLayout`;
2. derives instantaneous speed only from normal forward movement and clamped playback `dt`;
3. exponentially damps speed;
4. requests a target from `ReplayCameraSolver`;
5. snaps for reset/reduced-motion/paused seek/preset changes, otherwise uses Core smoothing;
6. applies finite position, look target, and FOV to the persistent `PerspectiveCamera`.

`ReplayView` owns `@State` for the selected preset and an incrementing reset generation. The existing renderer control row conditionally adds a menu-style Picker and icon-only reset button only for `.threeD`. The 3D surface passes drag, magnification, and double-click input to the controller only for `.orbit`.

## Effect Core Model

`ReplayEffectProfile.forSport(_:)` maps the three sports to fixed Phase 8C behavior:

| Sport | Wake | Spray | Offset | Wake capacity | Spray capacity | Droplets/catch/side |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| RowErg | foam | blade-tip | 2.2m | 24 | 48 | 4 |
| SkiErg | snow | pole-basket | 0.4m | 24 | 48 | 4 |
| BikeErg | none | none | none | 24 | 48 | 4 |

The capacities remain fixed even when a sport disables an effect, making the resource budget predictable.

`ReplayParticlePool` allocates a fixed backing array at initialization. Live entries occupy `0..<aliveCount`; expiry uses swap removal. `spawn` rejects invalid/expired particles and returns `false` at capacity. `update` applies velocity and caller-supplied gravity using finite non-negative `dt`, expires dead entries, and exposes a clamped life fraction for fade. `clear` changes only `aliveCount`.

`ReplaySprayGenerator.spawnCatch(...)` writes directly into an inout pool. Stable hash mixing combines catch ordinal, side, droplet index, and component lane to produce repeatable `0...1` values. It mirrors the web ranges for small position jitter, outward/trailing velocity, vertical launch, TTL, and size without `SystemRandomNumberGenerator` or per-frame arrays.

`ReplayWakeHistory` also allocates fixed backing storage. New points are inserted at the head while the oldest entry is recycled at capacity. Its update result distinguishes append, preserve, and clear:

- `distanceDelta > 0 && distanceDelta <= 30`: append;
- `distanceDelta == 0`: preserve;
- negative, non-finite, or `> 30`: clear;
- reduced motion: clear.

Age-indexed opacity and scale match the web trail shape: strongest near the participant, wider and fainter toward the tail.

## RealityKit Effect Renderer

`ReplayEffectRenderer` is created once by `Replay3DSceneBuilder`. It owns:

- one 24-entry live wake history and 24 prebuilt wake entities;
- one independent 24-entry ghost wake history and 24 prebuilt wake entities;
- one 48-entry live spray pool and 48 prebuilt droplet entities;
- shared wake and droplet meshes plus materials created during initialization.

The effect root and every child are attached during scene construction. Frame updates mutate only enabled state, position, orientation, scale, and opacity components. No frame update creates an entity, mesh, material, or array whose size can grow.

Wake positions trail behind each participant along its own course lane. Ghost wake uses a lower opacity multiplier. Catch spray uses `ReplayMotion.catchEvents(prev:next:)`, is gated by a fresh playback tick, positive normal movement, and non-zero `dt`, and is generated only for the live participant. Reduced motion/automation and scene resets clear both histories and the pool; a participant-only backward seek or teleport-sized movement clears only that participant's trail (and live spray for a live discontinuity). BikeErg keeps every effect entity disabled.

## Scene Lifecycle and Reset Rules

The RealityKit scene identity includes live workout ID, sport, and ghost ID. Workout/sport/ghost changes rebuild the bounded scene once. Switching away from 3D destroys its scene-local effect state; returning creates an empty scene while preserving playback and the `ReplayView` camera preset.

Per-update previous distance and phase values remain scene-local. A paused scrub updates participant/camera placement but cannot spawn spray. Backward or `>30m` movement clears wake history before any render. Reduced-motion/automation transitions clear effects immediately and keep them suppressed until disabled.

## Accessibility

- Camera Picker label: `Replay camera`; value is the current preset.
- Reset button label/help: `Reset replay camera`.
- 3D surface label remains `3D workout replay`; its value adds the selected camera name.
- No required action is gesture-only. The Picker and reset button remain keyboard and VoiceOver accessible.

## Test Strategy

### Core (Linux-compatible)

- Camera preset finite/distinct target poses, orbit clamping, non-finite fallback, FOV bounds, reduced-motion snap/fixed FOV, and equal-time damping at multiple frame rates.
- Particle capacity, full-pool rejection, integration/gravity, fade, expiry/swap removal, clear, non-finite safety, and deterministic catch generation.
- Wake fixed capacity, paused preservation, normal append, backward/non-finite/large-jump reset, reduced-motion reset, and sport-profile behavior.

### Studio (macOS)

- Build scenes for all sports and assert effect entity counts are fixed.
- Repeated updates leave the recursive entity count unchanged.
- Live and ghost histories advance independently.
- BikeErg never enables wake or spray.
- Reduced motion clears histories and particles.
- Existing replay navigation, renderer-mode, clock, and rig-structure assertions remain unchanged and pass.

## Documentation and Validation

Implementation and automated validation tasks are marked complete only after every required SwiftPM build/test command, architecture scan, staged bundle check, and diff check passes. The overall phase remains in progress while requested visual proof is unavailable. Visual QA and screenshots are recorded as evidence only when actually performed. Phase 8D remains not started and owns quality tiers, adaptive performance behavior, profiling, and final polish.
