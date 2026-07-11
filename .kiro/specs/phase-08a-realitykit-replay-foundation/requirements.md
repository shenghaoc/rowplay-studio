# Phase 8A Requirements: RealityKit 3D Replay Foundation

## R1: Renderer-Neutral Stroke Pose Model (RowPlayCore)

- **R1.1** `ReplayStrokePose` struct holds the per-frame pose state derived from a `ReplayFrame` and sport context. Fields: `index`, `phase`, `warpedPhase`, `cycleFrac`, `driveFrac`, `drive`, `driveProgress`, `recoveryProgress`, `strokeSeconds`, `strokeMeters`, `rate`, `watts`, `intensity`, `amplitude`, `fatigue`.
- **R1.2** `ReplayStrokePose.compute(frame:context:)` builds a pose from a `ReplayFrame` and a `ReplayStrokePoseContext` containing sport, peak watts, median watts, median distance-per-stroke, and max heart rate.
- **R1.3** All pose computation is pure, deterministic, and `Sendable`/`Equatable`. No RealityKit, SwiftUI, or platform imports.
- **R1.4** Port the web `strokeModel.ts` pose formulas: `driveFraction`, `secondsFromRate`, intensity normalization (watts 55%, dps 30%, rate 15%), fatigue from HR/progress/intensity, and amplitude from intensity/fatigue. Timeline normalization remains owned by the existing replay sampling path.
- **R1.5** `ReplayStrokePose.fallback(sport:phase:rate:)` produces a synthetic pose for workouts without stroke data, matching `fallbackStrokePose()`.
- **R1.6** All non-finite inputs (NaN, Infinity) are sanitized to safe defaults before reaching any computation.

## R2: Renderer-Neutral Course Layout (RowPlayCore)

- **R2.1** `ReplayCourseLayout` struct provides deterministic course placement on a 400-metre loop.
- **R2.2** `position(at:lane:)` returns a 3D position `(x, y, z)` for a given distance and lane offset.
- **R2.3** `tangent(at:)` returns the unit tangent direction at a distance.
- **R2.4** `headingAngle(at:)` returns the Y-axis rotation for facing travel direction.
- **R2.5** Distances beyond one lap wrap correctly (multiple laps). Negative distances produce valid positions.
- **R2.6** Non-finite distance or lane inputs produce a finite fallback position at the origin.
- **R2.7** All coordinates are renderer-neutral using simple `(Double, Double, Double)` tuples.

## R3: Parity Fixture

- **R3.1** A sanitized JSON parity fixture at `Tests/RowPlayCoreTests/Fixtures/stroke-pose-parity.json` contains representative web `strokePoseAt` outputs for RowErg, SkiErg, and BikeErg.
- **R3.2** The fixture is registered in `Package.swift` and loaded through `ParityFixtureLoader`.

## R4: Renderer Mode Enum (RowPlayStudio)

- **R4.1** `ReplayRendererMode` enum with `.twoD` and `.threeD` cases.
- **R4.2** Default is `.threeD`.

## R5: RealityKit Scene (RowPlayStudio)

- **R5.1** `RealityReplaySceneView` wraps a SwiftUI `RealityView` displaying a 3D course with live participant and optional ghost.
- **R5.2** The entity graph is created once in the `make` closure. Per-frame updates modify transforms/components only.
- **R5.3** A visible procedural 400-metre course with lane markings, start/finish marker, ground surface, directional lighting, fill lighting, and a perspective camera.
- **R5.4** Stable, restrained colors with clear contrast (not a one-hue blue or purple scene).
- **R5.5** Recognizable low-poly procedural placeholders for each sport:
  - **RowErg**: narrow hull/rail, seat, handle, athlete body.
  - **SkiErg**: upright frame, handles/poles, platform, athlete body.
  - **BikeErg**: frame, two wheels/flywheel, crank area, athlete body.
- **R5.6** Live position, orientation, bob/surge, and at least one articulated motion driven from `ReplayStrokePose`.
- **R5.7** Optional ghost rendered in its own lane with translucent material. Ghost uses its own replay frame/pose and never mutates live state.
- **R5.8** Uses `ReplayState` timeline as the single playback clock. No second timer.
- **R5.9** Fixed deterministic chase camera following the live participant smoothly without producing non-finite transforms.
- **R5.10** Reduced-motion preference: freeze repetitive body articulation and camera smoothing/bobbing; still allow scrubbing and progress updates.
- **R5.11** One accessibility element with label/value describing sport, progress, pace, cadence, ghost presence.
- **R5.12** Nonblank loading/failed state. RealityKit setup failure leaves the 2D selector usable.

## R6: ReplayView Integration

- **R6.1** Compact 2D/3D segmented picker added to `ReplayView`. Default is `.threeD`.
- **R6.2** Complete existing 2D renderer preserved as selectable fallback.
- **R6.3** Reuse existing playback controls, scrubber, telemetry, speed controls, keyboard behavior. No duplication.
- **R6.4** 3D scene is full-width and unframed within the replay surface. No decorative card.
- **R6.5** Stable aspect ratio/minimum height so mode switching does not resize surrounding layout.
- **R6.6** 2D/3D switching does not shift or overlap controls.

## R7: Test Coverage

- **R7.1** `ReplayStrokePoseTests`: web parity for all three sports, reduced motion, fallback cadence, fatigue/amplitude, non-finite inputs.
- **R7.2** `ReplayCourseLayoutTests`: loop boundaries, multiple laps, lanes, tangent direction, negative/non-finite input, finite output.
- **R7.3** RowPlayStudio tests for renderer-mode labels/default and view-independent scene configuration.
- **R7.4** Regression tests proving existing `ReplayState`/`ReplayMotion` behavior is unchanged.

## R8: Documentation

- **R8.1** Phase 8 added to `docs/roadmap.md`; only Phase 8A foundation marked complete.
- **R8.2** `docs/source-map.md` updated with web `renderer3d`/`strokeModel` to native Core/RealityKit mappings.
- **R8.3** `docs/beta-readiness.md` updated to mention RealityKit foundation without claiming final 3D replay.

## R9: Non-Goals

- No final high-detail athlete rigs, imported USD/USDZ assets, skinning, inverse kinematics.
- No particles, water simulation, interactive orbit camera, quality presets.
- No Metal shaders, SceneKit, Bluetooth, HR parsers, OAuth, public sharing.
- No unrelated refactors.
