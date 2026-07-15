# Phase 10A - Past-Session Ghost Replay — Design

## Architecture

```
RowPlayCore/Replay/
  GhostPick.swift          ← rankedGhostCandidates + pickDefaultGhostCandidate
  ReplayRaceGap.swift       ← raceGapMeters, raceGapSeconds, ghostFrame, etc.
  ReplaySample.swift        ← (unchanged, used by ReplayRaceGap)

RowPlayPlatform/
  WorkoutLibrary.swift      ← ghostCandidates(for:), defaultGhostCandidate(for:)

RowPlayStudio/Views/
  ContentView.swift         ← pass ghostCandidates to ReplayView
  ReplayView.swift          ← ghostCandidates, selectedGhostID, rival control, 2D ghost
  Replay3D/
    RealityReplaySceneView.swift  ← use ReplayRaceGap helpers
```

Dependency direction: Core → Platform → Studio. No UI frameworks in Core or Platform.

## Data Flow

1. WorkoutLibrary.ghostCandidates(for:) calls GhostPick.rankedGhostCandidates.
2. Ranked Workout values resolved to WorkoutDetail via detailByID.
3. ContentView passes [WorkoutDetail] to ReplayView.
4. ReplayView holds @State selectedGhostID: Int? (nil = no rival).
5. activeGhostDetail resolves from the fixed candidates snapshot.
6. Rival menu displays candidates; selection updates selectedGhostID.
7. 2D and 3D renderers read activeGhostDetail for ghost rendering.
8. ReplayRaceGap helpers compute live gap from ReplayState frame.

## GhostPick.rankedGhostCandidates

```
public static func rankedGhostCandidates(
    candidates: [Workout],
    current: GhostPickContext
) -> [Workout]
```

Steps:
1. Filter: exclude current ID, no stroke data, different sport, not comparable.
2. For distance-axis: sort by (matching distance band, closest distance, fastest pace, most recent date, stable ID).
3. For time-axis: sort by (matching duration band, closest duration, fastest pace, most recent date, stable ID).
4. pickDefaultGhostCandidate returns rankedGhostCandidates(...).first.

## ReplayRaceGap API

All pure, Sendable static methods on an enum:

- `raceGapMeters(playerD: Double, ghostD: Double) -> Double` — playerD - ghostD.
- `raceGapSeconds(gapM: Double, playerPace500m: Double) -> Double` — gapM / speed (speed = 500/pace).
- `relativeDuration(strokes: [Stroke]) -> TimeInterval` — last.t - first.t.
- `absoluteTime(elapsed: TimeInterval, strokes: [Stroke]) -> TimeInterval` — first.t + clamped elapsed.
- `ghostFrame(elapsed: TimeInterval, strokes: [Stroke]) -> ReplayFrame` — ReplaySample.sampleAt at absolute time.
- `ghostDistance(elapsed: TimeInterval, strokes: [Stroke]) -> Double` — ghostFrame(...).d.

## WorkoutLibrary Cache

```
private var ghostCandidateCache: (workoutID: Int, candidates: [WorkoutDetail])?
```

Invalidated in `updateAllDerivedData()` alongside `cachedComparisonCandidates`.
Resolved candidates must have non-empty strokes even if `hasStrokeData` is true.

## ReplayView Refactor

```
init(detail: WorkoutDetail, ghostCandidates: [WorkoutDetail] = [], initialGhostID: Int? = nil)
```

- Validates initialGhostID against candidates; invalid → nil.
- `activeGhostDetail` is a computed property: `candidates.first { $0.id == selectedGhostID }`.
- `onChange(of: selectedGhostID)`: increment replayDiscontinuityGeneration, clear 2D ghost path, recompute if canvas known.
- Replay3DSceneIdentity uses activeGhostDetail?.id.

## Rival Control Layout

```
[rendererPicker]          (existing)
[rival control band]      (new, full-width, no card)
[replaySurface]           (existing)
[telemetryBar]            (existing)
[playbackControls]        (existing)
```

Rival band: HStack with Menu(picker) + gap display + removal button.

## 2D Ghost Rendering

- Precomputed ghostPath stored as @State.
- Rebuilt on canvas size change, rival change, or workout change.
- Ghost path: purple with opacity ~0.35, lineWidth 1.5.
- Ghost playhead: purple dot at ghostDistance position on chart.
- Canvas accessibility value updated for rival-active state and gap.
