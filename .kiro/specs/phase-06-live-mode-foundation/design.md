# Phase 6 Design: Live Mode Foundation

## Architecture

All new live-mode domain logic lives in `RowPlayCore/Live/`:

- `Sources/RowPlayCore/Live/LiveModeState.swift` — pure state machine for polling lifecycle
- `Sources/RowPlayCore/Live/LivePollingCadence.swift` — interval computation, backoff, staleness
- `Sources/RowPlayCore/Live/LiveSource.swift` — injectable `LiveSource` protocol and `LivePollResult`
- `Sources/RowPlayCore/Live/MockLiveSource.swift` — demo source generating realistic workouts
- `Sources/RowPlayCore/Live/DemoLiveSampleGenerator.swift` — sequential in-progress sample generator

Native UI wiring lives in `RowPlayStudio/Views/`:

- `Sources/RowPlayStudio/Views/LiveModePanelView.swift` — SwiftUI panel with toggle, interval chips, status

## State Machine

`LiveModeState` is a value type (struct) with mutating transition methods. This keeps it fully testable without Combine or timers. The app layer (`WorkoutLibrary`) owns a `@Published` instance and drives transitions from its timer/callback layer.

Status transitions:

```
stopped ──start──▶ idle
idle ──pollStarted──▶ polling
polling ──pollSucceeded──▶ idle
polling ──pollFailed──▶ error
error ──pollStarted──▶ polling  (retry)
idle/error/any ──stop──▶ stopped
```

The `isStale(lastSampleAge:)` check compares the age against `2 × intervalSec`. This matches the web's implicit staleness heuristic where two missed polls means the data is suspect.

## Polling Cadence

`LivePollingCadence` is a stateless enum (namespace) with static methods, matching the pattern of `WorkoutAnalytics` and `WorkoutComparison`. It provides:

- `effectiveInterval(baseInterval:isVisible:)` — visibility throttle (300s min when hidden)
- `nextBackoffMs(consecutiveFailures:)` — exponential backoff: 30s → 60s → 120s → 300s cap
- `LIVE_INTERVALS` — the preset array `[30, 60, 120, 300]`

## Live Source Boundary

`LiveSource` is an `async throws` protocol so the mock can simulate delay and a future Concept2 client can make real network calls. The protocol returns `LivePollResult` which carries full `Workout` objects (not partial samples) so the library can ingest them directly.

`MockLiveSource` generates workouts by:
1. Picking a random sport from `Sport.allCases`
2. Generating a distance in a sport-appropriate range
3. Computing pace and time from the distance
4. Assigning an incrementing ID

It filters out already-known IDs in the `knownIDs` set parameter.

## Demo Live Sample Generator

`DemoLiveSampleGenerator` produces `LiveWorkoutSample` snapshots that simulate a workout in progress. Each call to `nextSample()` returns a sample with incrementally more distance and time, with slight pace variation. This is useful for UI development where you need to see values changing over time without a full poll cycle.

The generator is seeded for deterministic test output.

## Native UI

`LiveModePanelView` observes `WorkoutLibrary.liveState` and renders:

- A toggle bound to `liveState.enabled`
- A `Picker` with `SegmentedPickerStyle` for interval selection
- Status text showing last/next poll times using `Text(date:style:)`
- A warning badge when `consecutiveFailures >= 3`
- A progress indicator when status is `polling`

The panel is embedded in `DashboardView` below the existing metric tiles.

## WorkoutLibrary Integration

`WorkoutLibrary` gains:
- `@Published var liveState: LiveModeState`
- `func ingestLiveResult(_ result: LivePollResult)` — appends new workouts, deduplicates by ID
- A `LiveSource` property (defaulting to `MockLiveSource`) for the poll cycle

The library does not own the timer directly; the app or view layer drives polling via `DispatchQueue` or `TimelineView` to keep the store testable.

## Naming Conventions

- Swift `camelCase` for all properties (established).
- `LiveModeState` mirrors the web's `LiveMode` class shape but as a value type.
- `LiveSource.poll(knownIDs:)` mirrors the web's `apiPoll`/`demoPoll` split as a single protocol method.
- `LivePollResult` mirrors the web's `LivePollResult` interface.
