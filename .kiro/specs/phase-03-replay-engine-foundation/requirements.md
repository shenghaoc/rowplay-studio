# Phase 3 Requirements: Replay Engine and Native Renderer Foundation

## R1: Replay Sampling Model

The native app must port the web app's replay sampling engine into `RowPlayCore` so replay playback uses pure, testable interpolation logic.

- **R1.1** `ReplayFrame` struct holds interpolated workout state: `t` (TimeInterval), `d` (Double), `pace` (TimeInterval), `cadence` (Double), `heartRate` (Int?), `watts` (Int), `progress` (Double, 0...1).
- **R1.2** `sampleAt(strokes:t:)` linearly interpolates between bracketing strokes using binary search; clamps to first/last stroke at bounds.
- **R1.3** `sampleIndexAt(strokes:t:)` returns the index of the most recent stroke at or before `t` (sample-and-hold).
- **R1.4** Empty stroke arrays return a zeroed `ReplayFrame` with `progress` 0.
- **R1.5** Progress is computed as `t / totalTime`, clamped to 0...1.

## R2: Motion Timing Helpers

- **R2.1** `metersPerCycle(for:)` returns per-sport animation cycle distance (rower: 11m, skierg: 8m, bike: 5m).
- **R2.2** `clampDt(ms:)` converts milliseconds to seconds, clamping to max 0.1s; returns 0 for non-finite or non-positive input.
- **R2.3** `dampFactor(rate:dt:)` computes frame-rate independent smoothing: `1 - exp(-rate * max(0, dt))`.
- **R2.4** `warpStrokePhase(phase:driveFrac:)` remaps a continuous stroke phase so drive is quick and recovery is slow.
- **R2.5** `strokeSurge(warpedPhase:)` returns hull surge offset as `−cos(warpedPhase)`, range −1...1.
- **R2.6** `catchEvents(prev:next:maxCycles:)` counts phase boundary crossings between two phases, suppressing seek-sized jumps.

## R3: Comparability Guard

- **R3.1** `ComparabilityAxis` enum: `distance`, `time`.
- **R3.2** `classifyAxis(workoutType:)` maps Concept2 `workout_type` to axis: `JustRow` and `FixedTime` → time-axis; everything else → distance-axis.
- **R3.3** `areComparable(a:b:)` returns true only when same sport, same axis, and same axis-band (distance band or duration band).
- **R3.4** `DurationBand` struct and `WorkoutAnalytics.durationBand(for:)` bucket workout durations into bands matching the web app's `durationBand()`.

## R4: Ghost Selection

- **R4.1** `GhostPickContext` struct: `id`, `distance`, `sport`, `time`, `workoutType`.
- **R4.2** `pickDefaultGhostCandidate(candidates:current:)` picks the best ghost rival: same comparability band, closest metric, fastest pace, most recent.
- **R4.3** For time-axis pieces, rank by closeness in elapsed time (not distance band).
- **R4.4** Excludes the current workout from candidates.

## R5: Sport Theme

- **R5.1** `ReplaySportTheme` struct with `label` and `cadenceUnit`.
- **R5.2** `sportTheme(for:)` returns the correct theme per sport (RowErg/spm, SkiErg/spm, BikeErg/rpm).
- **R5.3** Machine hex colors for light and dark mode (for canvas rendering).

## R6: Replay Inspector

- **R6.1** `distancePerStroke(stroke:)` computes metres per stroke from pace and cadence; returns nil when invalid.
- **R6.2** `splitIndexAt(splits:distance:)` returns the split/interval index for a given cumulative distance.

## R7: Replay State Machine

- **R7.1** `ReplayState` class manages playback: `time`, `playing`, `speed`, `duration`, `currentFrame`.
- **R7.2** Methods: `play()`, `pause()`, `toggle()`, `seek(to:)`, `setSpeed(_:)`.
- **R7.3** `tick(deltaTime:)` advances time by `dt * speed` and updates `currentFrame`.
- **R7.4** Auto-pauses when reaching the end of the workout.
- **R7.5** Speed presets: 0.5x, 1x, 1.5x, 2x, 4x.
- **R7.6** Seek clamps to `[0, duration]`.

## R8: SwiftUI Replay Surface

- **R8.1** `ReplayView` provides a SwiftUI Canvas-based 2D replay surface.
- **R8.2** Displays telemetry overlay: current pace, distance, cadence, watts, heart rate.
- **R8.3** Playback controls: play/pause button, scrubber slider, speed picker.
- **R8.4** Uses demo stroke data from `DemoWorkoutLibrary`.
- **R8.5** Accessible from `WorkoutDetailView` when workout has stroke data.

## R9: Test Coverage

- **R9.1** `ReplaySampleTests`: empty strokes, bounds clamping, exact timestamps, interpolation, heart rate handling, ghost coherence.
- **R9.2** `ReplayMotionTests`: clampDt, dampFactor frame-rate independence, warpStrokePhase monotonicity, strokeSurge bounds, catchEvents.
- **R9.3** `ComparabilityGuardTests`: classifyAxis, areComparable sport/axis/band matching.
- **R9.4** `GhostPickTests`: band preference, self-exclusion, no candidates, time-axis ranking, tie-breaking.
- **R9.5** `ReplayInspectorTests`: distancePerStroke validity, splitIndexAt mapping.
- **R9.6** `ReplayStateTests`: play/pause, seek, speed, auto-pause, frame emission.
- **R9.7** `swift test` passes.
- **R9.8** `swift build` passes.

## R10: Non-Goals

- No Concept2 sync, Keychain, SQLite, or network code.
- No Metal, SceneKit, or 3D rendering.
- No share/export flows.
- No Bluetooth/hardware connectivity.
- No synchronized telemetry charts (future sub-phase).
- No reduced-motion handling (future sub-phase).
