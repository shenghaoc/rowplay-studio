# Phase 8D Tasks: Adaptive Replay Quality and Performance Profiling

## Spec

- [x] Create `requirements.md` with exact budgets, adaptive semantics, architecture, persistence, accessibility, test, telemetry, visual-QA, and documentation requirements.
- [x] Create `design.md` with selected/effective ownership, governor/metrics algorithms, tick pairing, inner-scene rebuilds, bounded RealityKit updates, and test strategy.
- [x] Create this task list without pre-marking implementation or validation work.

## RowPlayCore Quality and Effects

- [x] Add `ReplayRenderQuality.swift` with four cases, default medium, exact configurations, and bounded one-way degradation helpers.
- [x] Update `ReplayEffectProfile` to accept a configuration and remove Phase 8C's fixed 24/48 capacities.
- [x] Support exact zero-to-ultra fixed capacities, safely clamp negative/oversized requests, and preserve deterministic spray/wake behavior.
- [x] Preserve BikeErg, ghost, seek, pause, reduced-motion, and zero-capacity semantics.

## RowPlayCore Performance

- [x] Add `ReplayPerformanceGovernor.swift` with 22/30/60/90 defaults, median calibration, capped budget, EMA, grace, sticky step-down, reset, and invalid-sample rejection.
- [x] Add `ReplayPerformanceMetrics.swift` with a fixed 120-sample scalar accumulator and bounded snapshots.
- [x] Keep both implementations portable, value-semantic, allocation-bounded, and free of timers/sleeps/platform APIs.

## RowPlayPlatform Persistence

- [x] Add `AppPreferences.replayRenderQuality` with the `replayRenderQuality` UserDefaults key and default-medium/corrupt fallback.
- [x] Persist all four selected ceilings and synchronize external UserDefaults changes.
- [x] Confirm effective quality, governor level, metrics, and logs are never persisted.
- [x] Leave `SettingsView` unchanged.

## Playback Clock and Studio Controller

- [x] Extend `ReplayPlaybackClock` to expose first-frame-aware raw delta alongside the clamped playback delta.
- [x] Add `ReplayPerformanceController` with selected/effective quality, governor/metrics ownership, generation deduplication, bounded pending tick pairing, and scene/selection resets.
- [x] Add `ReplayPerformanceTelemetry` with selection, degradation, and 120-sample window events only.
- [x] Keep per-frame controller state non-observable and never mutate `ReplayState` from performance code.

## Quality-Aware RealityKit Scene

- [x] Pass the effective configuration into `Replay3DSceneBuilder` and build exact ring/marker budgets while retaining distance and start/finish markers.
- [x] Allocate exact tier-sized wake/spray entity arrays once per graph; low allocates zero and BikeErg keeps all allocated effects inactive.
- [x] Update active prefixes only and disable only newly inactive tails without repeated inactive opacity/component writes.
- [x] Rebuild only the inner RealityView on manual selection or one-tier degradation.
- [x] Preserve replay time/state/speed, camera preset, and orbit across graph rebuilds while resetting effects.
- [x] Use 30 Hz for low and 60 Hz for other Timeline minimum intervals; measure scene updates once per real generation with `ContinuousClock`.

## Quality UI and Accessibility

- [x] Add the 3D-only Low/Medium/High/Ultra menu Picker beside camera controls in `ReplayView`.
- [x] Bind the Picker to `preferences.replayRenderQuality` and report selected/effective tiers through accessibility value and help.
- [x] Add the accessible/helped adaptive-reduction status icon only when effective quality is below the ceiling.
- [x] Preserve the 2D UI and avoid control, telemetry, or playback overlap.

## Tests

- [x] Add `ReplayRenderQualityTests.swift` for exact budgets/default/degradation/capacity/BikeErg cases.
- [x] Add `ReplayPerformanceGovernorTests.swift` for health, 30 Hz calibration, overload, spike, grace, maximum, invalid samples, overloaded calibration, and reset without sleep.
- [x] Add `ReplayPerformanceMetricsTests.swift` for exact window timing, averages/maxima, budget count, invalid samples, and reset.
- [x] Update `ReplayEffectsTests.swift` for quality-driven budgets without weakening Phase 8C behavior assertions.
- [x] Expand `AppPreferencesTests.swift` for default/all cases/external sync/corrupt fallback/non-persistence.
- [x] Add `ReplayQualitySceneTests.swift` for graph budgets, effect allocations, BikeErg, fixed counts, state preservation, controller steps/deduplication, and inactive-tail writes.
- [x] Update playback-clock tests for raw/clamped/first-frame behavior.
- [x] Keep all existing camera, effect, rig, replay, navigation, accessibility, and 2D tests passing.

## Documentation

- [x] Update `docs/roadmap.md` with merged Phase 8C truth and implemented Phase 8D scope/evidence.
- [x] Update `docs/source-map.md` for quality policy, governor, metrics, raw sampling, persistence, Studio controller, and quality UI.
- [x] Update `docs/beta-readiness.md` with actual Phase 8D validation, telemetry observations, visual QA, and remaining production-performance gaps.
- [x] Preserve the historical unavailable Phase 8C trackpad-magnification, production-route ghost, and exact-1440x900 checks without retroactive completion claims.
- [x] Record only actual Phase 8D telemetry numbers, visual cases, screenshots, and unavailable checks in this file.

## Focused Validation

- [x] `swift test --filter ReplayRenderQualityTests`
- [x] `swift test --filter ReplayPerformanceGovernorTests`
- [x] `swift test --filter ReplayPerformanceMetricsTests`
- [x] `swift test --filter ReplayEffectsTests`
- [x] `swift test --filter ReplayCameraTests`
- [x] `swift test --filter AppPreferencesTests`
- [x] `swift test --filter ReplayQualitySceneTests`
- [x] `swift test --filter Replay3DSceneEffectsTests`
- [x] `swift test --filter ReplayNavigationTests`

## Complete Validation

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

## Telemetry and Visual/Performance QA

- [x] Capture one quality-selection event and at least one completed metrics-window event with the `replay-performance` subsystem/category filter.
- [x] Confirm captured logs contain no workout IDs, account data, tokens, filenames, stroke values, or per-frame lines.
- [x] Record complete RowErg low, medium, and ultra metric windows as observations only.
- [x] Inspect RowErg low/medium/high/ultra, SkiErg low/ultra, and BikeErg low/ultra.
- [x] Confirm tier density, low/Bike effect suppression, restrained enabled effects, and playback/camera/orbit stability through live quality changes.
- [x] Exercise chase/side/overhead/orbit, pause/resume, backward/forward seek, reduced motion/automation, unchanged 2D mode, and minimum/largest available windows.
- [x] List screenshots actually captured and explicitly list any unavailable exact 1440x900, trackpad, ghost, Instruments, profiling, or other requested proof.

### Captured Phase 8D evidence

- RowErg low, 120 samples: 34.167 ms average / 100.000 ms worst frame interval; 0.067 ms average / 0.190 ms worst scene update.
- Rebased-head telemetry schema recheck, RowErg low, 120 samples: 37.778 / 166.667 ms frame interval; 0.064 / 0.154 ms scene update; overBudget=35. The event omits a singular budgetMs value because the window compares samples against their per-sample active budgets.
- RowErg medium, 120 samples: 24.583 / 166.667 ms frame interval; 0.124 / 0.299 ms scene update.
- RowErg ultra, 120 samples: 27.222 / 216.666 ms frame interval; 0.191 / 0.360 ms scene update.
- Local Computer Use captures: `phase8d-rowerg-low.png`, `phase8d-rowerg-medium-active.png`, `phase8d-rowerg-high-overhead.png`, `phase8d-rowerg-ultra.png`, `phase8d-rowerg-2d.png`, `phase8d-ski-low.png`, `phase8d-ski-ultra.png`, `phase8d-bike-low.png`, `phase8d-bike-ultra.png`, and `phase8d-largest-window.png`. These are validation captures under `/private/tmp`, not repository assets.
- Unavailable: exact 1440x900 (largest available was 1308x768), trackpad magnification, production-route ghost replay, and Instruments profiling. A degradation event was not forced on the healthy machine; governor tests are the deterministic proof.

## Final Audit and Publication

- [x] Confirm only Phase 8D files changed, no open-PR overlap, no dependency/toolchain changes, forbidden imports, per-frame logging/allocation, unbounded history, weakened tests, TODO placeholders, or optimistic claims.
- [x] Commit as `feat: Phase 8D - Adaptive replay quality`.
- [x] Push `codex/phase-08d-adaptive-replay-quality`.
- [x] Open the focused draft PR with the required title/body and actual validation evidence.
- [x] Leave the PR draft and unmerged.
