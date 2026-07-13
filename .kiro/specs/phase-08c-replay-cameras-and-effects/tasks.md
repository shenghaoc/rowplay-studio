# Phase 8C Tasks: Replay Cameras and Sport Effects

## Spec

- [x] Create `requirements.md` with camera, effects, accessibility, architecture, test, documentation, and validation requirements.
- [x] Create `design.md` with finite camera math, bounded effect lifecycles, RealityKit ownership, reset semantics, and test strategy.
- [x] Create this task list without pre-marking implementation or validation work.

## RowPlayCore Camera

- [x] Add `Sources/RowPlayCore/Replay/ReplayCamera.swift`.
- [x] Add `ReplayCameraPreset`, clamped `ReplayCameraOrbit`, finite `ReplayCameraPose`, and deterministic `ReplayCameraSolver`.
- [x] Implement chase, side, overhead, and orbit target poses.
- [x] Implement 46...51 degree speed-aware chase FOV and stable non-chase FOV.
- [x] Implement frame-rate-independent smoothing through `ReplayMotion.dampFactor(rate:dt:)`.
- [x] Implement non-finite fallback and reduced-motion fixed-FOV/snap behavior.

## RowPlayCore Effects

- [x] Add `Sources/RowPlayCore/Replay/ReplayEffects.swift`.
- [x] Add sport profiles with RowErg 2.2m, SkiErg 0.4m, and BikeErg-disabled behavior.
- [x] Add fixed-capacity 48-droplet particle pool with deterministic spawn, integration, gravity, fade, expiry, clear, and full-pool behavior.
- [x] Add deterministic catch-spray generation with 4 droplets per side and no system randomness.
- [x] Add fixed-capacity 24-entry wake history with paused preservation and backward/non-finite/>30m reset behavior.
- [x] Clear and suppress transient effects for reduced motion.

## RowPlayStudio Camera

- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayCameraController.swift`.
- [x] Move finite camera target/smoothing application out of the scene builder into the controller.
- [x] Make `ReplayView` own camera preset selection and reset generation.
- [x] Add 3D-only compact camera Picker/menu and accessible reset button with macOS help.
- [x] Add orbit-only drag and magnification plus double-click reset.
- [x] Preserve full-width unframed RealityKit layout and every existing 2D/playback/ghost behavior.

## RowPlayStudio Effects

- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayEffectRenderer.swift`.
- [x] Prebuild all live-wake, ghost-wake, and live-spray entities, meshes, and materials when the scene is created.
- [x] Add RowErg foam wake/blade spray and SkiErg snow trail/pole-basket spray.
- [x] Keep BikeErg free of wake and catch spray.
- [x] Keep ghost wake independent and lower-opacity; keep spray live-only.
- [x] Trigger spray through `ReplayMotion.catchEvents` without emitting on seeks or paused frames.
- [x] Reset effects for workout, sport, renderer, reduced-motion, automation, backward seek, and large jump changes.
- [x] Keep repeated frame updates allocation-bounded and entity-count stable.

## Tests

- [x] Add `Tests/RowPlayCoreTests/Replay/ReplayCameraTests.swift` with all preset, finite, clamp, FOV, reduced-motion, and damping cases.
- [x] Add `Tests/RowPlayCoreTests/Replay/ReplayEffectsTests.swift` with pool, deterministic spray, wake, profile, seek, and reduced-motion cases.
- [x] Add `Tests/RowPlayStudioTests/Replay3DSceneEffectsTests.swift` with fixed entity count, live/ghost independence, BikeErg suppression, and reduced-motion clearing.
- [x] Keep existing ReplayState, ReplayMotion, 2D replay, navigation, and rig assertions unchanged and passing.

## Documentation

- [x] Update `docs/roadmap.md` and keep Phase 8D not started.
- [x] Update `docs/source-map.md` for web camera, `WakeTrail`, `ParticlePool`, and catch-spray mappings.
- [x] Update `docs/beta-readiness.md` with truthful Phase 8C scope and remaining gaps.
- [x] Mark completed implementation tasks only after their corresponding validation passed.

## Validation

- [x] `swift build --target RowPlayCore`
- [x] `swift test --filter RowPlayCoreTests`
- [x] `swift build --target RowPlayPlatform`
- [x] `swift test --filter RowPlayPlatformTests`
- [x] `swift test --filter RowPlayStudioTests`
- [x] `swift test`
- [x] `swift build`
- [x] `git diff --check`
- [x] Core forbidden-import scan returns no matches.
- [x] Platform forbidden-UI-import scan returns no matches.
- [x] `./script/build_and_run.sh --verify`
- [x] `./script/build_and_run.sh --automation`
- [x] `./script/build_and_run.sh --sign-verify`
- [ ] Complete the full requested visual-QA matrix.
  - [x] Inspected all three sport scenes, all four cameras, orbit drag/double-click reset, pause/resume, backward/forward seek, 2D regression, reduced-motion/automation suppression, the app's 1000-point minimum-width layout, and the largest 1307x768 window available in this environment without overlaps.
  - [ ] Trackpad magnification was unavailable through the Computer Use bridge.
  - [ ] Ghost visual QA was unreachable because the production replay route does not supply `ghostDetail`; automated tests cover independent lower-opacity ghost state.
  - [ ] Exact 1440x900 inspection was unavailable because the desktop's largest captured app window was 1307x768.
- [x] Final status/diff review confirms only Phase 8C scope, no dependency/toolchain upgrade, no forbidden imports, no unrelated redesign, and no fabricated validation claims.
