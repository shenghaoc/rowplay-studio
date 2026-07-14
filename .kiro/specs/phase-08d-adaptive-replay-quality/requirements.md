# Phase 8D Requirements: Adaptive Replay Quality and Performance Profiling

## R1: Architecture and Scene-State Boundaries

- **R1.1** `RowPlayCore` owns the portable render-quality policy, tier configuration, adaptive governor, and bounded performance metrics. It contains no SwiftUI, AppKit, RealityKit, Charts, Combine, Security, OSLog, SF Symbol names, or platform timers.
- **R1.2** `RowPlayPlatform` persists only the user's selected quality ceiling through `AppPreferences` and `UserDefaults`.
- **R1.3** `RowPlayStudio` owns SwiftUI controls, RealityKit graph construction, scene-local performance coordination, `ContinuousClock` measurement, and unified logging.
- **R1.4** Dependency direction remains `RowPlayStudio -> RowPlayPlatform -> RowPlayCore`. No external dependency, toolchain, CI-runner, or deployment-target change is permitted.
- **R1.5** Selected quality is a persisted ceiling. Effective quality, governor level, calibration, frame samples, metrics, and performance logs are ephemeral scene state and are never persisted.
- **R1.6** Quality changes and adaptive degradation never mutate `ReplayState`, navigation state, playback speed, camera selection, or camera orbit state.

## R2: Render-Quality Tiers

- **R2.1** Add `ReplayRenderQuality` with `low`, `medium`, `high`, and `ultra` cases plus a renderer-neutral `ReplayRenderConfiguration`.
- **R2.2** The default selected ceiling is `medium`.
- **R2.3** The exact tier budgets are:

| Tier | Course ring segments | Lane markers | Wake entries / participant | Spray particles | Droplets / side / catch | Target FPS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Low | 48 | 24 | 0 | 0 | 0 | 30 |
| Medium | 72 | 48 | 16 | 40 | 4 | 60 |
| High | 96 | 64 | 28 | 48 | 4 | 60 |
| Ultra | 144 | 96 | 44 | 72 | 6 | 60 |

- **R2.4** Low creates no wake or spray entities. BikeErg may retain the selected tier's fixed allocation but keeps every wake and spray inactive at every tier.
- **R2.5** Automatic degradation is one-way and one tier per step: `ultra -> high -> medium -> low`, `high -> medium -> low`, `medium -> low`, and `low` remains `low`.
- **R2.6** Adaptive quality never upgrades automatically. Manual or externally synchronized selection resets the scene governor and starts at the newly selected ceiling.

## R3: Quality-Aware Bounded Effects

- **R3.1** `ReplayEffectProfile` accepts a render configuration and replaces the Phase 8C hard-coded 24-wake/48-spray budget.
- **R3.2** Particle and wake backing storage supports the ultra maxima of 72 particles and 44 entries without growing after initialization.
- **R3.3** Negative capacities clamp to zero and oversized capacities clamp to the corresponding ultra maximum without trapping or unbounded allocation.
- **R3.4** Zero-capacity wake and particle pools remain valid and silently reject new entries.
- **R3.5** Existing deterministic spray, fixed-capacity storage, swap expiry, wake recycling, seek/pause/ghost behavior, BikeErg suppression, and reduced-motion clearing remain intact.

## R4: Calibrated Sticky Performance Governor

- **R4.1** Add a Swift value-semantic `ReplayPerformanceGovernor` with defaults of a 22 ms floor budget, 30 calibration frames, 60 sustained-over-budget frames, 90 grace frames after degradation, and the selected tier's available degradation steps as its maximum level.
- **R4.2** Non-finite, non-positive, and greater-than-250 ms intervals are ignored without mutating calibration, grace, EMA, counters, or level.
- **R4.3** Calibration uses the median observed raw frame interval and computes `min(floor * 2, max(floor, median * 1.6))` as the active budget.
- **R4.4** After calibration, the governor maintains `previous * 0.9 + sample * 0.1` as its exponential moving average.
- **R4.5** A degradation occurs only after the configured consecutive over-budget window. A healthy sample resets the over-budget counter.
- **R4.6** Each degradation clears the over-budget counter and EMA, begins the grace period, increments by one level, never exceeds its maximum, and never reverses automatically.
- **R4.7** A steady approximately 33.4 ms display does not degrade solely for operating near 30 Hz, while approximately 100 ms calibration remains capped and can degrade under sustained load.
- **R4.8** The governor uses no timers, sleeps, queues, or platform APIs.

## R5: Bounded Performance Metrics

- **R5.1** Add a fixed 120-sample `ReplayPerformanceMetrics` accumulator with no growing history.
- **R5.2** Each valid sample records raw frame interval, scene-update duration, the active budget comparison, sums, worst values, and count.
- **R5.3** A snapshot is emitted only on the 120th valid sample and contains sample count, average/worst frame interval, average/worst scene-update duration, and count above the active budget.
- **R5.4** Counters reset immediately after a snapshot. Non-finite or otherwise invalid inputs do not advance the window.
- **R5.5** Metrics contain no workout IDs, stroke data, user/account data, filenames, tokens, timestamps, or unbounded sample arrays.

## R6: Persisted Selected Ceiling

- **R6.1** `AppPreferences` adds the `replayRenderQuality` key and a published `ReplayRenderQuality` property.
- **R6.2** Missing, unknown, wrong-type, or corrupt values fall back to `medium`.
- **R6.3** All four cases persist when changed through `AppPreferences`, and external `UserDefaults` changes synchronize back into the property.
- **R6.4** Effective quality, governor state, frame metrics, and logs are never written to `UserDefaults`.
- **R6.5** `SettingsView` remains unchanged. PR #56 owned that file when Phase 8D began, so this phase keeps its control in `ReplayView` even though PR #56 has since merged.

## R7: Raw Playback Intervals and Deduplication

- **R7.1** `ReplayPlaybackClock` exposes a first-frame-aware raw interval, the existing `ReplayMotion`-clamped playback delta, and the new last-tick date.
- **R7.2** `ReplayState.tick` receives only the clamped delta; the governor receives the raw interval in milliseconds.
- **R7.3** First frames and pauses produce no performance sample. Seek/control/gesture-triggered RealityView refreshes do not duplicate a real playback sample.
- **R7.4** One monotonic `playbackTickGeneration` identifies each real playback tick for raw-frame and scene-duration pairing.

## R8: Studio Performance Coordination and Telemetry

- **R8.1** Add an `@MainActor` `ReplayPerformanceController` that owns the governor and metrics, tracks selected/effective quality, pairs one raw interval with one measured scene duration per generation, and rejects duplicate generations.
- **R8.2** Only selected/effective tier transitions are observable by SwiftUI. Per-frame intervals, durations, governor internals, counters, and metrics do not publish view updates.
- **R8.3** New-scene and manual-selection resets clear calibration, degradation, pending samples, metrics, and generation tokens. Degradation remains sticky for the current scene.
- **R8.4** Add `ReplayPerformanceTelemetry` using subsystem `com.shenghaoc.RowPlayStudio` and category `replay-performance`.
- **R8.5** Telemetry emits one bounded line for a quality selection, one for an adaptive degradation, and one per completed metrics window. It never logs every frame and never uses `print`.
- **R8.6** Only tier names, governor levels, sample counts, and numeric timing measurements use public log privacy. Sensitive or workout-specific data is never logged.

## R9: Quality-Aware RealityKit Scene

- **R9.1** `Replay3DSceneBuilder` accepts an effective render configuration and builds exactly its ring-segment and lane-marker counts while retaining eight distance markers and the start/finish marker.
- **R9.2** `ReplayEffectRenderer` allocates exactly the effective tier's live-wake, ghost-wake, and live-spray entity capacities once during scene creation. No per-frame entity, mesh, material, or growing-array allocation is permitted.
- **R9.3** Effect updates touch active prefixes only. When a count shrinks, only the newly inactive tail is disabled; already inactive entities do not receive repeated opacity/component writes.
- **R9.4** Independent live/ghost state, lower ghost opacity, deterministic catch spray, BikeErg suppression, and reduced-motion/automation suppression remain intact.
- **R9.5** `RealityReplaySceneView` rebuilds only its inner RealityView when effective quality changes. User selection and a one-step governor degradation are the only quality-rebuild triggers.
- **R9.6** A quality rebuild preserves replay time, play/pause state, speed, camera preset, and orbit state, while resetting effect histories so no cross-course trail or catch burst appears.
- **R9.7** Low uses a 30 Hz Timeline minimum interval; medium, high, and ultra use 60 Hz. No timer, display link, task loop, or independent playback clock is added.
- **R9.8** Scene-update duration is measured with `ContinuousClock` and recorded once for a valid pending playback generation. Sampling occurs only for real 3D playback ticks.

## R10: Quality Control and Accessibility

- **R10.1** `ReplayView` adds a compact 3D-only native menu Picker beside the camera controls for Low, Medium, High, and Ultra, bound to `preferences.replayRenderQuality`.
- **R10.2** The Picker uses a familiar Studio-owned icon, has accessibility label `3D replay quality`, states both selected and effective tiers in its accessibility value, and has a concise macOS help tooltip.
- **R10.3** When effective quality is below the selected ceiling, an `arrow.down.circle` status icon identifies the effective tier for accessibility and explains in help text that quality was reduced to maintain replay performance.
- **R10.4** No explanatory card or paragraph is added, controls do not overlap existing renderer/camera/telemetry/playback controls, and the 2D replay UI is unchanged.

## R11: Tests, Validation, and Documentation

- **R11.1** Core tests cover exact tier budgets/degradation, capacity bounds/zero pools/BikeErg behavior, governor calibration/degradation/reset/invalid input, and exact 120-sample metrics behavior without sleep.
- **R11.2** Platform tests cover default, all persisted values, external synchronization, corrupt fallback, and non-persistence of ephemeral state.
- **R11.3** Studio tests cover exact scene/effect counts, zero-effect low, BikeErg suppression, fixed entity counts, rebuild state preservation, one-step degradation, generation deduplication, inactive-tail write behavior, and raw/clamped clock results.
- **R11.4** Existing Phase 8C effect/camera, rig, replay, navigation, accessibility, and 2D assertions are updated for parameterized budgets but never weakened or deleted.
- **R11.5** Focused tests, the full SwiftPM matrix, architecture scans, staged bundle, automation, signing, telemetry, visual/performance QA, and final diff audit are recorded exactly as run. Phase 8D is complete only if every required gate actually passes.
- **R11.6** Documentation records observed metrics as observations only and makes no universal frame-rate, benchmark-improvement, GPU-scaling, production-asset, production-performance, or hardware-connectivity claim.
- **R11.7** Phase 8C is corrected to merged PR #57 while preserving the historical truth that trackpad magnification, production-route ghost replay, and exact 1440x900 inspection were unavailable before merge and are not retroactively claimed.

## Non-Goals

- Automatic quality upgrades, oscillation, WebGL DPR scaling, WebGPU fallback logic, or browser storage APIs.
- Metal, SceneKit, custom shaders, imported USD/USDZ assets, animated water deformation, or unsupported RealityKit shadow APIs.
- Bluetooth/CoreBluetooth/FTMS/Concept2 PM transport, external dependencies, toolchain/CI/deployment-target upgrades, timers, display links, task loops, or per-frame logging.
- Settings changes, files owned by PR #55, broad UI/2D redesign, unrelated refactors, or optimistic/fabricated validation claims.
