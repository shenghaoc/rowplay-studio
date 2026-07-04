# Phase 6 Requirements: Live Mode Foundation

## R1: Live Mode State Machine

The native app must model live-mode polling state as a pure, testable state machine in `RowPlayCore`.

- **R1.1** `LiveModeStatus` enum defines states: `idle`, `polling`, `error`, `stopped`.
- **R1.2** `LiveModeState` tracks `enabled`, `status`, `intervalSec`, `consecutiveFailures`, `lastPollAt`, and `nextPollAt`.
- **R1.3** `LiveModeState` transitions are driven by explicit events: `start`, `stop`, `pollStarted`, `pollSucceeded`, `pollFailed`, `tickScheduled`, `intervalChanged`.
- **R1.4** The state machine enforces that `pollStarted` is only valid when status is `idle` or `error`; successive `pollStarted` events while `polling` are ignored.
- **R1.5** `LiveModeState.isStale(lastSampleAge:)` returns true when the most recent sample exceeds a staleness threshold derived from the current interval (2× the configured interval).
- **R1.6** `LiveModeState` only accepts supported interval presets and falls back to 60 seconds for invalid initial values.

## R2: Polling Cadence and Backoff

The native app must compute polling intervals with visibility-aware throttling and exponential backoff.

- **R2.1** `LivePollingCadence.effectiveInterval(baseInterval:isVisible:)` returns the base interval when visible, or a minimum of 300 seconds when the app is not frontmost.
- **R2.2** `LivePollingCadence.nextBackoffMs(consecutiveFailures:)` returns exponential backoff steps: 30s, 60s, 120s, 300s cap.
- **R2.3** After a successful poll, backoff resets to zero.
- **R2.4** Interval presets are `[30, 60, 120, 300]` seconds, matching the web app.

## R3: Live Source Boundary

The native app must define an injectable protocol for live workout data so mock and future real sources share the same interface.

- **R3.1** `LiveSource` protocol defines `func poll(knownIDs: Set<Int>) async throws -> LivePollResult`.
- **R3.2** `LivePollResult` struct contains `workouts: [Workout]` and `added: Int`; aggregate totals and PB celebrations are deferred until real sync wiring is added.
- **R3.3** `MockLiveSource` generates deterministic demo workouts at varying intervals for QA and UI development.
- **R3.4** `MockLiveSource` produces workouts with realistic sport distribution, distance ranges, and timing.
- **R3.5** `MockLiveSource` is stateful: it tracks generated IDs and increments them to avoid collisions.

## R4: Demo Live Samples

The native app must generate realistic live workout samples for testing and demo purposes.

- **R4.1** `LiveWorkoutSample` struct records a partial in-progress workout snapshot: `id`, `sport`, `distance`, `time`, `pace`, `strokeRate`, `heartRateAvg`, and `date`.
- **R4.2** `DemoLiveSampleGenerator` produces sequential samples that simulate a workout progressing over time (distance increasing, pace varying slightly).
- **R4.3** Generated samples use the same `Sport` and `Workout` model types as completed workouts.
- **R4.4** Sample generation is deterministic when seeded, for test reproducibility.

## R5: Live Mode Panel

The native app must provide a SwiftUI panel that displays live-mode controls and status.

- **R5.1** `LiveModePanelView` shows an enable/disable toggle.
- **R5.2** When enabled, it shows interval selector chips (30s, 1m, 2m, 5m).
- **R5.3** It displays polling status: last poll time, next poll countdown, or a "polling" indicator.
- **R5.4** It shows a warning indicator after 3+ consecutive failures.
- **R5.5** The panel displays an in-progress mock workout sample that can update without credentials.
- **R5.6** The panel is backed by `WorkoutLibrary` live state and demo sample data.

## R6: Native UX and Module Boundaries

- **R6.1** All live-mode domain logic lives in `RowPlayCore/Live/`.
- **R6.2** The live-mode panel lives in `RowPlayStudio/Views/LiveModePanelView.swift`.
- **R6.3** `WorkoutLibrary` gains a `liveState` property and a method to ingest live poll results.
- **R6.4** `WorkoutLibrary` owns the current demo live sample and advances it when the panel starts or refreshes mock polling.
- **R6.5** The dashboard exposes the live panel in its layout.
- **R6.6** Standard macOS controls: toggle, interval buttons, icon-only refresh button with help text, status text with monospaced digits.
- **R6.7** `WorkoutLibrary.ingestLiveResult(_:)` appends new live workouts while deduplicating existing and duplicate incoming workout IDs.

## R7: Test Coverage

- **R7.1** `LiveModeStateTests` cover all state transitions, stale detection, and backoff computation.
- **R7.2** `LivePollingCadenceTests` cover effective interval, backoff steps, and backoff reset.
- **R7.3** `MockLiveSourceTests` cover poll returns, ID incrementing, and sport distribution.
- **R7.4** `DemoLiveSampleGeneratorTests` cover deterministic sample generation and progression.
- **R7.5** `swift test` passes.
- **R7.6** `swift build` passes.

## R8: Non-Goals

- No Bluetooth or direct hardware connectivity.
- No full Concept2 production polling (deferred to Phase 7 unless Phase 4 boundaries cleanly support it).
- No replay renderer rewrites.
- No public sharing or export changes.
- No background daemons or menu bar behavior.
- No audio chime or notification sounds.
- No UserDefaults/cookie persistence of live prefs (deferred; native uses in-memory state for this PR).
