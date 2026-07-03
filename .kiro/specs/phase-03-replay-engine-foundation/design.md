# Phase 3 Design: Replay Engine and Native Renderer Foundation

## Goal

Port the web app's pure replay sampling, motion timing, ghost selection, comparability guard, sport theme, and inspector logic into `RowPlayCore`. Add a native replay state machine for play/pause/scrub/speed control. Create a first SwiftUI Canvas replay surface using demo stroke data. Keep renderer work modest: 2D native foundation only.

## Architecture

### 1. Replay Sampling (`RowPlayCore/Replay/ReplaySample.swift`)

Ports `engine.ts` `sampleAt` and `sampleIndexAt` as pure Swift functions:

- `ReplayFrame` value type holding interpolated workout state at a point in time.
- `sampleAt(strokes:t:)` uses binary search to find bracketing strokes, then linearly interpolates all fields. Clamps to first/last stroke at bounds. Returns zeroed frame for empty input.
- `sampleIndexAt(strokes:t:)` returns the lower bracket index (sample-and-hold).
- Uses the existing `Stroke` model from `RowPlayCore/Models/Workout.swift`. Maps `cadence` (native) to `spm` (web) semantics.

### 2. Motion Timing (`RowPlayCore/Replay/ReplayMotion.swift`)

Ports `motion.ts` pure animation helpers:

- `metersPerCycle(for:)` — per-sport animation cycle distance.
- `clampDt(ms:)` — frame delta clamping (max 100ms).
- `dampFactor(rate:dt:)` — frame-rate independent exponential smoothing.
- `warpStrokePhase(phase:driveFrac:)` — drive/recovery phase warping using piecewise linear remapping.
- `strokeSurge(warpedPhase:)` — hull surge offset via cosine.
- `catchEvents(prev:next:maxCycles:)` — catch crossing detection with seek suppression.

All pure math, no dependencies.

### 3. Comparability Guard (`RowPlayCore/Replay/ComparabilityGuard.swift`)

Ports `comparabilityGuard.ts`:

- `ComparabilityAxis` enum: `.distance`, `.time`.
- `classifyAxis(workoutType:)` — maps Concept2 workout_type strings to axis.
- `areComparable(a:b:)` — hard-block predicate checking sport, axis, and band equality.
- `ComparableContext` protocol/struct for the comparison inputs.
- Depends on `WorkoutAnalytics.distanceBand` and the new `durationBand`.

### 4. Duration Band (`RowPlayCore/Analytics/WorkoutAnalytics.swift`)

Adds `DurationBand` struct and `durationBand(for:)` method parallel to `distanceBand(for:)`:
- Standard durations: 60, 240, 1200, 1800, 3600 seconds (±10% tolerance).
- Range bands: <90s, 90s–6m, 6–15m, 15–40m, 40–80m, 80m+.

### 5. Ghost Selection (`RowPlayCore/Replay/GhostPick.swift`)

Ports `ghostPick.ts`:

- `GhostPickContext` value type with id, distance, sport, time, workoutType.
- `pickDefaultGhostCandidate(candidates:current:)` — filters by comparability, ranks by band match, distance/time closeness, pace, recency.
- Time-axis pieces rank by elapsed time closeness, not distance band.
- Excludes the current workout by id.

### 6. Sport Theme (`RowPlayCore/Replay/ReplaySportTheme.swift`)

Ports `sports.ts`:

- `ReplaySportTheme` struct with label and cadence unit.
- `sportTheme(for:)` static lookup.
- `MachineColor` struct with light/dark hex values for canvas rendering.

### 7. Replay Inspector (`RowPlayCore/Replay/ReplayInspector.swift`)

Ports `inspector.ts`:

- `distancePerStroke(stroke:)` — metres per stroke from pace and cadence.
- `splitIndexAt(splits:distance:)` — split index for cumulative distance.

### 8. Replay State Machine (`RowPlayCore/Replay/ReplayState.swift`)

Native equivalent of `ReplayEngine` from `engine.ts`, adapted for tick-based driving:

- `ReplayState` class with published properties: `time`, `playing`, `speed`, `duration`, `currentFrame`.
- `tick(deltaTime:)` advances by `dt * speed`, updates frame, auto-pauses at end.
- `play()`, `pause()`, `toggle()`, `seek(to:)`, `setSpeed(_:)`.
- Speed presets: 0.5, 1.0, 1.5, 2.0, 4.0.
- SwiftUI `TimelineView` or `CADisplayLink` drives the ticks externally.

### 9. SwiftUI Replay View (`Sources/RowPlayStudio/Views/ReplayView.swift`)

First 2D replay surface:

- `Canvas` drawing a simplified stroke path visualization.
- Telemetry overlay showing current frame metrics.
- Playback controls: play/pause button, scrubber `Slider`, speed `Picker`.
- Uses `DemoWorkoutLibrary` data by default.
- Navigated from `WorkoutDetailView` via sheet or navigation link.

## File Layout

```
Sources/RowPlayCore/
  Replay/
    ReplaySample.swift              (new)
    ReplayMotion.swift              (new)
    ComparabilityGuard.swift        (new)
    GhostPick.swift                 (new)
    ReplaySportTheme.swift          (new)
    ReplayInspector.swift           (new)
    ReplayState.swift               (new)
  Analytics/
    WorkoutAnalytics.swift          (modify — add durationBand)
Sources/RowPlayStudio/
  Views/
    ReplayView.swift                (new)
    WorkoutDetailView.swift         (modify)
Tests/RowPlayCoreTests/
  Replay/
    ReplaySampleTests.swift         (new)
    ReplayMotionTests.swift         (new)
    ComparabilityGuardTests.swift   (new)
    GhostPickTests.swift            (new)
    ReplayInspectorTests.swift      (new)
    ReplayStateTests.swift          (new)
```

## Non-Goals

- No Concept2 sync, Keychain, SQLite, or network code.
- No Metal, SceneKit, or 3D rendering.
- No share/export flows.
- No Bluetooth/hardware connectivity.
