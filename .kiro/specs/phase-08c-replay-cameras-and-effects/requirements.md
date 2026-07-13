# Phase 8C Requirements: Replay Cameras and Sport Effects

## Overview

Phase 8C adds selectable replay cameras and restrained, sport-specific wake and catch-spray effects to the existing RealityKit replay. Camera and effect simulation remain deterministic and renderer-neutral in `RowPlayCore`; SwiftUI interaction and RealityKit entities remain in `RowPlayStudio`.

## R1: Architecture and Determinism

- **R1.1** `RowPlayCore` owns renderer-neutral camera solving, particle simulation, wake history, effect profiles, distance-delta reset rules, and deterministic spray variation. `RowPlayStudio` owns scene lifecycle and reset-generation wiring.
- **R1.2** `RowPlayStudio` owns SwiftUI controls and gestures plus RealityKit cameras, entities, meshes, materials, and transform application.
- **R1.3** `RowPlayCore` must not import SwiftUI, AppKit, RealityKit, Charts, Combine, or Security. `RowPlayPlatform` must not import SwiftUI, AppKit, RealityKit, or Charts.
- **R1.4** Core camera/effect models are `Sendable` and `Equatable` where value semantics apply, contain portable scalar values only, and sanitize non-finite input.
- **R1.5** Frame updates use no system randomness. Catch-spray variation is derived from a stable catch ordinal and deterministic seed mixing.
- **R1.6** `ReplayState` remains the only playback clock. Phase 8C adds no timer or display-link source.

## R2: Renderer-Neutral Camera Model

- **R2.1** Add `ReplayCameraPreset` with `chase`, `side`, `overhead`, and `orbit` cases.
- **R2.2** Add `ReplayCameraOrbit` with clamped yaw, pitch, and distance. Yaw is normalized to `-π...π`, pitch is clamped to `10°...75°`, and distance is clamped to `4...30` metres.
- **R2.3** Add `ReplayCameraPose` containing finite scalar camera position, look target, and field of view.
- **R2.4** Add `ReplayCameraSolver` that returns deterministic finite target poses from a participant position, course tangent, finite replay speed, orbit state, and reduced-motion state.
- **R2.5** Chase follows from behind and slightly outside the course tangent, with a readable three-quarter view and look-ahead target.
- **R2.6** Side provides a stable lateral athlete/equipment view. Overhead shows course position while keeping the participant in view. Orbit applies user yaw, pitch, and distance around the live participant.
- **R2.7** Chase field of view may vary only within `46...51` degrees using finite replay speed. Side, overhead, and orbit use a stable field of view.
- **R2.8** Camera smoothing uses `ReplayMotion.dampFactor(rate:dt:)` and is equivalent over equal wall-clock time at different frame rates.
- **R2.9** Reduced motion fixes field of view at 46 degrees and disables camera interpolation.
- **R2.10** NaN, infinity, degenerate tangents, invalid speed, and invalid current poses fall back to finite deterministic values before reaching RealityKit.

## R3: Camera Controls and Gestures

- **R3.1** `ReplayView` owns the selected camera preset so switching between 2D and 3D never changes playback state or loses the camera selection.
- **R3.2** Camera controls appear only while 3D is selected.
- **R3.3** A compact native Picker/menu uses a camera SF Symbol and exposes the current preset. An icon-only reset button restores the default orbit and current preset target.
- **R3.4** Camera controls have explicit accessibility labels, values where useful, and macOS help tooltips.
- **R3.5** Drag changes orbit yaw/pitch only in orbit mode. Trackpad magnification changes orbit distance only in orbit mode. Double-clicking the 3D surface resets orbit.
- **R3.6** The 3D surface remains full-width, unframed, and free of visible instructional text.
- **R3.7** Existing replay playback, scrubber, speed, keyboard, ghost, renderer switching, and 2D behavior remain intact.

## R4: Sport Effect Profiles

- **R4.1** Add `ReplayEffectProfile` selected by `Sport`.
- **R4.2** RowErg enables a restrained white foam wake and blade-tip catch spray with a `2.2` metre lateral spawn offset.
- **R4.3** SkiErg enables a restrained snow trail and pole-basket catch spray with a `0.4` metre lateral spawn offset.
- **R4.4** BikeErg has no wake and no catch spray.
- **R4.5** Medium-quality limits are fixed for this phase: 24 wake entries per visible participant, 48 live spray droplets, and 4 droplets per side per catch.
- **R4.6** A visible ghost receives an independent wake with lower opacity. Catch spray is live-participant only.

## R5: Bounded Particle and Wake Simulation

- **R5.1** Add a fixed-capacity `ReplayParticlePool` whose backing storage is allocated once. Spawn, integration, gravity, fade, expiry, swap removal, clear, and full-pool drop behavior are deterministic and bounded.
- **R5.2** The particle pool never exceeds capacity and silently rejects additional droplets when full.
- **R5.3** Add a fixed-capacity `ReplayWakeHistory` whose backing storage is allocated once. Positive movement appends/recycles entries; zero movement preserves history.
- **R5.4** Backward seeks, negative distance deltas, non-finite deltas, and jumps over 30 metres clear wake history instead of drawing a cross-course trail.
- **R5.5** Reduced motion clears wake and particle state and suppresses new transient effects.
- **R5.6** Catch spray is triggered through `ReplayMotion.catchEvents`. Paused frames, seeks, large jumps, backward motion, and renderer resets emit no catch burst.

## R6: RealityKit Effect Rendering

- **R6.1** Add `ReplayEffectRenderer` with independent live-wake, ghost-wake, and live-spray state.
- **R6.2** Every effect `ModelEntity`, `MeshResource`, and material is built once with the scene. Per-frame updates change existing transforms, visibility, scale, and opacity only.
- **R6.3** Per-frame updates do not create entities, meshes, materials, or unbounded arrays, and repeated updates do not change the scene entity count.
- **R6.4** Changing workout, sport, renderer mode, or reduced-motion/automation state clears stale effects. A newly built scene begins with empty histories and particles.
- **R6.5** Reduced-motion and automation mode suppress and clear transient effects.
- **R6.6** Sport surface colors/materials may be refined, but course meshes are neither rebuilt nor deformed per frame.
- **R6.7** Deterministic demo mode remains fully functional.

## R7: Accessibility and Interaction Safety

- **R7.1** The 3D surface remains one meaningful accessibility element and its value includes the selected camera preset in addition to sport, progress, telemetry, and ghost state.
- **R7.2** Camera selection and reset are reachable without gestures. Gestures supplement, rather than replace, explicit controls.
- **R7.3** Camera and effect input sanitization prevents non-finite RealityKit transforms, scales, or field-of-view values.

## R8: Test Coverage

- **R8.1** Linux-compatible Core tests cover every camera preset, distinct preset placement, orbit bounds, non-finite fallback, chase FOV bounds, reduced-motion behavior, and frame-rate-independent damping.
- **R8.2** Linux-compatible Core tests cover particle capacity/full-pool behavior, integration, gravity, fade, expiry, clear, deterministic spray, wake capacity, paused preservation, seek/jump reset, sport profiles, and reduced-motion clearing.
- **R8.3** Studio tests cover stable scene entity count across repeated updates, independent live/ghost effect histories, BikeErg suppression, and reduced-motion clearing.
- **R8.4** Existing `ReplayState`, `ReplayMotion`, 2D replay, navigation, and articulated-rig assertions are not weakened or removed and continue to pass.
- **R8.5** Existing assertions are not weakened or removed to accommodate Phase 8C.

## R9: Documentation and Validation

- **R9.1** Update `docs/roadmap.md`, `docs/source-map.md`, `docs/beta-readiness.md`, and this phase's `tasks.md` to match implemented behavior and actual validation.
- **R9.2** Mark Phase 8C complete only after the complete build/test/architecture/bundle validation matrix passes. Keep Phase 8D not started.
- **R9.3** Documentation must not claim imported USD/USDZ assets or proven final production 3D performance.
- **R9.4** Visual QA records only sports, cameras, gestures, seek/reset cases, ghost cases, reduced-motion/automation cases, and window sizes that were actually inspected.

## Non-Goals

- Quality tiers, quality preferences, `PerfGovernor`, or adaptive degradation.
- Metal, SceneKit, custom shaders, a second 3D renderer, or imported USD/USDZ assets.
- External dependencies, Bluetooth/CoreBluetooth/FTMS/Concept2 PM transport, toolchain changes, deployment-target changes, or new timers.
- Broad UI redesign, unrelated cleanup, or AppKit work unless a narrowly scoped SwiftUI gesture proves insufficient.
