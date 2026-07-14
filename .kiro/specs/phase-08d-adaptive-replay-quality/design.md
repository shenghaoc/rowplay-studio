# Phase 8D Design: Adaptive Replay Quality and Performance Profiling

## Architecture

```text
RowPlayCore/Replay/
|- ReplayRenderQuality.swift
|  |- ReplayRenderQuality
|  `- ReplayRenderConfiguration
|- ReplayPerformanceGovernor.swift
|- ReplayPerformanceMetrics.swift
`- ReplayEffects.swift (configuration-driven fixed capacities)

RowPlayPlatform/
`- AppPreferences.swift (selected ceiling only)

RowPlayStudio/Views/Replay3D/
|- ReplayPerformanceController.swift
|- ReplayPerformanceTelemetry.swift
|- RealityReplaySceneView.swift
|- Replay3DSceneBuilder.swift
`- ReplayEffectRenderer.swift

RowPlayStudio/Views/ReplayView.swift
`- persisted quality Picker plus effective-tier status
```

Core remains portable and renderer-neutral. Platform persists one enum raw value. Studio converts configuration integers into RealityKit graph sizes, coordinates the scene-local governor, measures monotonic update duration, and logs bounded privacy-safe summaries.

## Selected and Effective Quality

`ReplayRenderQuality.defaultQuality` is `.medium`. Each case exposes one immutable `ReplayRenderConfiguration` containing the exact course, marker, wake, spray, droplets-per-side, and target-frame-rate budget.

The selected quality is a ceiling. `maximumDegradationLevel` is 0/1/2/3 for low/medium/high/ultra. `nextLowerQuality` and bounded `degraded(by:)` helpers encode the one-way ladder without loops proportional to untrusted input.

`AppPreferences.replayRenderQuality` persists only the selected case's raw value. `ReplayPerformanceController.effectiveQuality` begins at that tier, moves down exactly one tier when the governor emits a new level, and never writes back to preferences. A manual or external selected-quality change resets governor calibration and metrics and returns effective quality to the selected tier.

## Quality-Aware Effect Storage

`ReplayEffectProfile.forSport(_:configuration:)` retains the RowErg 2.2m and SkiErg 0.4m offsets, deterministic catch generation, and BikeErg-disabled flags while taking all capacities from the configuration. BikeErg keeps a predictable tier-sized allocation but never activates it. Low has zero-sized allocations for every sport.

`ReplayParticlePool` and `ReplayWakeHistory` clamp requested capacities into `0...72` and `0...44`. Arrays are allocated exactly once. Zero-capacity instances short-circuit spawn/update paths safely. The Phase 8C deterministic hash, swap removal, newest-first wake recycling, discontinuity clearing, ghost independence, and reduced-motion behavior are preserved.

## Performance Governor

`ReplayPerformanceGovernor` is a mutable Swift struct. It owns a fixed calibration array, sample count, optional calibrated budget, EMA, consecutive-over-budget count, grace counter, and current level.

Valid samples are finite, positive, and at most 250 ms. The first 30 populate calibration. On the 30th sample, a one-time sorted copy selects the upper middle value (matching the tested web implementation) and calculates:

```text
activeBudget = min(floorBudget * 2,
                   max(floorBudget, median * 1.6))
```

The pre-calibration active budget is the 22 ms floor. After calibration and outside grace, each valid sample updates `ema = ema * 0.9 + sample * 0.1`. Healthy frames clear the consecutive-over-budget counter. Sixty consecutive over-budget EMA results increment the level once, clear EMA/counter, and start 90 valid-frame grace. Invalid samples mutate nothing. Reset reuses the fixed buffer while restoring the initial state.

## Bounded Metrics

`ReplayPerformanceMetrics` keeps only scalar sums, maxima, counts, and the fixed window size. It stores no per-sample array. `record(...)` accepts a valid raw frame interval, non-negative finite scene duration, and positive finite active budget. It increments the above-budget count when the frame interval exceeds that sample's active budget.

The 120th valid sample returns `ReplayPerformanceMetricsSnapshot`, then clears the accumulator. Snapshot fields are numeric and context-free: sample count, average/worst frame interval, average/worst scene duration, and above-budget count.

## Playback Tick Pairing

`ReplayPlaybackClock.Tick` separates:

- `rawDelta`: `nil` for the first post-resume frame, otherwise the unmodified wall-clock interval;
- `delta`: `ReplayMotion.clampDt` output used by playback/camera/effects;
- `lastTickDate`: the new clock anchor.

`RealityReplaySceneView` increments `playbackTickGeneration` once per playing Timeline callback. It sends raw milliseconds to `ReplayPerformanceController.recordFrameInterval(...)` before ticking `ReplayState` with the clamped delta.

The controller keeps at most one pending `(generation, raw interval, active budget)` tuple. A matching RealityView update is measured with `ContinuousClock` and completes that tuple exactly once. Duplicate gesture/control refreshes carry the same generation and are ignored. First frames, pauses, seeks, invalid intervals, app-background-sized intervals, and 2D mode create no completed performance sample.

## Controller Observation and Telemetry

`ReplayPerformanceController` is `@MainActor` and `@Observable`, but only `effectiveQuality` participates in observation. Governor state, metrics, pending tuples, generation tokens, and counters are observation-ignored. Per-frame work therefore does not invalidate SwiftUI.

The controller feeds the governor from the Timeline event callback so a rare degradation changes observable state outside `RealityView.update`. Scene-duration completion mutates only non-observable metrics. Selection/reset and degradation call `ReplayPerformanceTelemetry` once; a completed 120-sample snapshot logs once.

The OSLog subsystem/category is `com.shenghaoc.RowPlayStudio` / `replay-performance`. Lines contain only event type, selected/effective tier, level, sample count, averages/maxima, and above-budget count. No workout or user context is accepted by the telemetry API.

## RealityKit Rebuild and Entity Updates

`Replay3DSceneBuilder.buildScene` requires the effective configuration. It uses exact named ring and lane-marker loops so tests can count the actual graph, while retaining the existing eight distance markers and start/finish cells. The configuration is stored on the container only for diagnostics.

`ReplayEffectRenderer` constructs shared meshes/materials and exactly `wake * 2 + spray` entities for the effective tier. It tracks the previous rendered count for live wake, ghost wake, and spray. Each update mutates `0..<activeCount`; a shrink disables only `activeCount..<previousCount`. `disable` is a no-op when an entity is already disabled, preventing repeated inactive opacity writes.

Only the inner RealityView is keyed by effective quality. The outer `RealityReplaySceneView` retains its binding to `ReplayState`, `ReplayCameraController`, selected camera, orbit values, clock anchor, and controller. A new graph resets effects and camera smoothing; `ReplayCameraController.resetSceneState()` intentionally preserves orbit. Quality changes do not enter the outer `Replay3DSceneIdentity`.

The Timeline minimum interval derives from `configuration.targetFrameRate`: 1/30 second at low and 1/60 second otherwise. No new clock source drives playback.

## ReplayView Control and Accessibility

`ReplayView` owns a small `effectiveReplayQuality` state used only to report the child controller's effective tier. In 3D mode the existing control row adds an icon-only menu Picker bound to `preferences.replayRenderQuality`. Studio supplies user-facing capitalization and `slider.horizontal.3`; Core supplies neither labels nor symbols.

The Picker's accessibility value always states selected and effective tiers. A conditional `arrow.down.circle` appears only when effective is lower, with an explicit accessible label and help explaining the performance reduction. The renderer Picker, camera controls, telemetry, playback controls, and 2D layout are otherwise unchanged.

## Test Strategy

### Core

- Exact four-tier budgets, default medium, degradation bounds, and low floor.
- Quality-driven sport profiles, ultra support, negative/oversized capacity clamps, zero-capacity pools, deterministic spray, BikeErg suppression, and all existing Phase 8C effect semantics.
- 60 Hz and steady 30 Hz health, sustained overload, single-spike recovery, grace, maximum level, invalid intervals, overloaded calibration, and reset without sleeps.
- Exact 120-sample snapshot timing, averages/maxima, budget count, invalid-sample rejection, and reset without history.

### Platform

- Default/corrupt fallback, every raw value load/persist, external notification synchronization, and an isolated-domain check that no effective/governor/metrics key exists.

### Studio

- Named course and marker counts for every tier, exact effect allocations, low zero allocation, BikeErg inactive effects, fixed entity count, and active-tail-only disabling.
- Controller one-tier degradation, sticky level, selection reset, and duplicate-generation rejection.
- Raw versus clamped playback clock, inner-graph rebuild with preserved `ReplayState`, camera/orbit structural ownership, and all Phase 8C/replay/navigation/2D regressions.

## Validation and Historical Evidence

Focused tests run before the complete Core/Platform/Studio matrix. Architecture scans, bundle launch, automation, signing, subsystem-filtered telemetry, visual tier/sport/camera/seek/window QA, and final diff audit follow. Documentation is updated only with commands, observed metrics, screenshots, and manual checks actually completed.

Phase 8C merged to `main` as PR #57. Its automated gates passed, but trackpad magnification, the production-route ghost replay, and exact 1440x900 inspection were unavailable before merge. Phase 8D preserves those limits as historical facts rather than converting them into completed proof.
