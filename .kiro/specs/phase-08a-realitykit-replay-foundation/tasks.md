# Phase 8A Tasks: RealityKit 3D Replay Foundation

## Spec

- [x] Create `requirements.md`
- [x] Create `design.md`
- [x] Create `tasks.md`

## RowPlayCore

- [x] Add `Sources/RowPlayCore/Replay/ReplayStrokePose.swift`
- [x] Port `strokePoseAt` / `fallbackStrokePose` / `driveFraction` / `secondsFromRate` from web `strokeModel.ts`
- [x] All fields: `index`, `phase`, `warpedPhase`, `cycleFrac`, `driveFrac`, `drive`, `driveProgress`, `recoveryProgress`, `strokeSeconds`, `strokeMeters`, `rate`, `watts`, `intensity`, `amplitude`, `fatigue`
- [x] `ReplayStrokePoseContext` with sport, peakWatts, medianWatts, medianDPS, maxHR
- [x] Sanitize non-finite inputs (pace, cadence, phase, progress, timing)
- [x] `Equatable`, `Sendable`, portable numeric values only
- [x] Support RowErg, SkiErg, BikeErg semantics
- [x] Add `Sources/RowPlayCore/Replay/ReplayCourseLayout.swift`
- [x] 400-metre loop, renderer-neutral coordinates
- [x] `position(at:lane:)`, `tangent(at:)`, `headingAngle(at:)`
- [x] Multiple laps wrap, negative distance handled, non-finite fallback
- [x] Add parity fixture `Tests/RowPlayCoreTests/Fixtures/stroke-pose-parity.json`
- [x] Register fixture in `Package.swift`

## RowPlayStudio

- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplayRendererMode.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/RealityReplaySceneView.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/Replay3DSceneBuilder.swift`
- [x] Add `Sources/RowPlayStudio/Views/Replay3D/ReplaySportModels.swift`
- [x] `RealityView` with persistent entity graph
- [x] Procedural 400m course with lane markings, start/finish, ground, lighting
- [x] Sport-specific low-poly placeholders (RowErg, SkiErg, BikeErg)
- [x] Live position/orientation/bob/surge from `ReplayStrokePose`
- [x] Articulated motion (oars, poles, pedals)
- [x] Ghost in separate lane with translucent material, sampled on the live replay's elapsed clock
- [x] Chase camera with smooth interpolation
- [x] Reduced-motion: freeze articulation, disable camera smoothing
- [x] Accessibility element with label/value
- [x] Loading/failed state
- [x] Update `ReplayView` with 2D/3D segmented picker

## Tests

- [x] `ReplayStrokePoseTests.swift`: web parity, three sports, reduced motion, fallback, fatigue, non-finite
- [x] `ReplayCourseLayoutTests.swift`: loop boundaries, laps, lanes, tangent, negative/non-finite
- [x] RowPlayStudio tests: renderer-mode labels/default
- [x] Regression: existing `ReplayStateTests`, `ReplayMotionTests` unchanged

## Documentation

- [x] Update `docs/roadmap.md` — Phase 8A foundation complete
- [x] Update `docs/source-map.md` — strokeModel/renderer3d mappings
- [x] Update `docs/beta-readiness.md` — RealityKit foundation mentioned

## Validation

- [x] `swift test --filter ReplayStrokePoseTests` — 27 tests, 0 failures
- [x] `swift test --filter ReplayCourseLayoutTests` — 22 tests, 0 failures
- [x] `swift test --filter ReplayStateTests` — 16 tests, 0 failures (regression)
- [x] `swift test --filter ReplayMotionTests` — 19 tests, 0 failures (regression)
- [x] `swift build --target RowPlayCore` — clean build
- [x] `swift test --filter RowPlayCoreTests` — 784 tests, 0 failures, 2 skipped
- [x] `swift test --filter RowPlayStudioTests` — 7 tests, 0 failures
- [x] `swift test` — all test targets pass; 2 authenticated smoke tests skipped
- [x] `swift build` — clean build
- [x] `git diff --check` — no whitespace errors
- [x] `./script/build_and_run.sh --verify` — app launches successfully
- [x] Architecture violation check: rg returns no violations in Core or Platform
