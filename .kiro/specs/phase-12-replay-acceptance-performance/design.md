# Phase 12 Design — Replay Acceptance and Performance Hardening

## Architecture

```
script/launch_replay_acceptance.sh
  → script/build_and_run.sh --acceptance --stage-only
  → dist/RowPlayStudio.app with ROWPLAY_REPLAY_ACCEPTANCE=1 + QA env

RowPlayStudioApp
  → AppLaunchConfiguration (acceptance vs automation vs normal)
  → ReplayAcceptanceHarnessView
      → production ReplayView(initialConfiguration:)
          → Replay2DSceneView / RealityReplaySceneView
          → ReplayPerformanceController
              → ReplayAcceptanceMetricsStore (QA only)
```

Dependency direction remains `RowPlayStudio → RowPlayPlatform → RowPlayCore`.
No SwiftUI/AppKit/RealityKit in Core or Platform. No new dependencies.

## Launch configuration flow

1. `AppLaunchConfiguration.make(from:)` reads environment.
2. When `ROWPLAY_REPLAY_ACCEPTANCE=1`, `ReplayAcceptanceConfiguration.parse`
   validates every QA key and returns a finite Sendable value object.
3. Invalid values throw fixed public diagnostics; process launch exits non-zero.
4. Acceptance forces `WorkoutLibrary.automationDemo()`, disables sync, and
   roots the window on `ReplayAcceptanceHarnessView`.
5. Normal and `ROWPLAY_AUTOMATION` paths remain unchanged.

## Scenario catalog

`script/replay_acceptance_scenarios.json` holds stable IDs and values. The
launch script maps one ID to environment variables. The harness maps sport to a
fixed demo workout:

| Sport | Demo workout ID |
| --- | ---: |
| rower | 1001 |
| skierg | 1003 |
| bike | 1004 |

## Production ReplayView reuse

`ReplayViewInitialConfiguration` is an internal, defaulted parameter. Production
call sites stay source-compatible. Acceptance supplies renderer, camera,
quality, seek time, rival mode, and Reduced Motion without writing
`AppPreferences`.

## Metrics pipeline

- Production `ReplayPerformanceController` continues to pair frame intervals
  with RealityKit update durations.
- When acceptance is active, the same paired samples feed
  `ReplayAcceptanceMetrics` (cap 600).
- Summary percentiles use nearest-rank on the bounded sample arrays.
- Output is either one privacy-safe log event or one JSON file under
  `ROWPLAY_QA_OUTPUT`.

## xctrace / RSS workflow

`script/profile_replay.sh`:

1. Launches the scenario through the acceptance script.
2. Attaches Time Profiler when listed by `xcrun xctrace list templates`.
3. Records Core Animation / Metal templates only when listed.
4. Samples resident set size at fixed intervals.
5. Writes a compact summary without user data or absolute private paths.
6. Leaves `.trace` bundles in the caller-supplied output directory.

## Evidence storage

Committed evidence lives under `docs/visual-qa/phase-12-replay-acceptance/`:

- `README.md` assessment
- `manifest.json` sanitized scenario outcomes
- selected representative screenshots only

Raw traces, private machine paths, and unbounded log dumps are excluded.

## Failure and privacy handling

- Invalid QA environment → fixed public diagnostic, no launch.
- Metrics write failure → public log category only.
- No tokens, account data, imported filenames, workout identifiers, or stroke
  payloads in manifests or acceptance logs.
