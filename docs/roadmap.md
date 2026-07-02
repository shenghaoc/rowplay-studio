# RowPlay Studio Native Roadmap

This roadmap ports rowplay from SvelteKit/Cloudflare to native macOS first while keeping the core library usable for a future iOS target. Phase 0 is committed directly to `main` to establish the scaffold. Phase 1 onward should use separate branches and pull requests.

## Phase 0 - Native Bootstrap

Status: in progress in the initial direct-to-main scaffold.

Scope:

- Create the SwiftPM package, `RowPlayStudio` executable app, and `RowPlayCore` library.
- Establish native macOS shell conventions: `WindowGroup`, `NavigationSplitView`, toolbar commands, settings scene, and deterministic demo data.
- Port the first domain models: `Sport`, `Workout`, `Stroke`, `Split`, `WorkoutDetail`.
- Port basic formatting and analytics: Concept2 pace-to-watts semantics, sport summaries, total/challenge distance, distance bands, and linear trends.
- Add `script/build_and_run.sh`, Codex Run action, and a macOS CI workflow.

Exit criteria:

- `swift test` passes.
- `swift build` passes.
- `./script/build_and_run.sh --verify` launches the app bundle on a local macOS machine.
- The first commit lands directly on `main`.

## Phase 1 - Core Parity Foundation

Status: in progress on `codex/phase-01-core-parity-foundation`.

Scope:

- Port the pure TypeScript helpers that do not depend on Cloudflare or the DOM: datetime handling, pace input parsing, personal bests, performance predictor, and privacy redaction.
- Build fixture parity against the web app's golden demo workouts.
- Introduce a `RowPlayCoreTests/Fixtures` strategy so native and web calculations can be compared without hand-inspecting charts.

Exit criteria:

- Native unit tests cover every ported helper.
- Differences from web behavior are documented with product rationale.
- No UI changes beyond exposing newly available core summaries.

## Phase 2 - Native Dashboard And Library

Scope:

- Port `workoutQuery.ts` pure query/filter/sort engine into `RowPlayCore/Library/WorkoutQuery.swift`.
- Wire `WorkoutQuery` into `WorkoutLibrary` store so filtering/sorting is not view-local math.
- Add sidebar sort menu, sport segmented picker, PB badge on workout rows.
- Enhance dashboard with personal bests grid, per-sport summary cards, challenge distance metric.
- Add `WorkoutQueryTests` covering filter, sort, chip toggling, PB detection, and edge cases.

Exit criteria:

- The native dashboard is usable offline with imported or demo data.
- Dashboard calculations come from `RowPlayCore`, not view-local math.
- `swift test` and `swift build` pass.

Status: in progress on `codex/phase-02-native-dashboard-library`.

## Phase 3 - Replay Engine And Native Renderer

Scope:

- Port replay sampling, motion timing, ghost selection, comparability guard, sport-specific semantics, and replay inspector logic.
- Implement a native SwiftUI Canvas replay first, then decide whether Metal/SceneKit is justified for 3D.
- Add playback controls, scrubber, speed control, synchronized telemetry charts, reduced-motion handling, and ghost racing.

Exit criteria:

- Replay can run from deterministic demo data without a network connection.
- Sampling and ghost selection match web fixtures.
- Rendering choices are validated with screenshots and performance measurements on macOS.

## Phase 4 - Concept2 Sync, Privacy, And Local Storage

Scope:

- Implement BYOT Concept2 token entry with Keychain storage.
- Add a URLSession Concept2 client and a local SQLite-backed workout cache.
- Preserve rowplay's privacy invariant: tokens do not enter logs, exported fixtures, or analytics payloads.
- Keep Cloudflare-specific KV/D1 assumptions out of native core.

Exit criteria:

- A user can sync Concept2 workouts into the native local cache.
- Disconnect/delete purges local cached data and Keychain token state.
- Privacy-sensitive logs are redacted and covered by tests.

## Phase 5 - Compare, Export, Share, And Annotations

Scope:

- Add side-by-side comparison, interval/rep comparison, HR import, private annotations, CSV/JSON/TCX export, and share workflows.
- Decide whether share links are generated through a companion web service or exported as local replay packages.

Exit criteria:

- Exported data round-trips with the web app where formats overlap.
- Share behavior is explicit about which data becomes public.
- Annotation and HR import flows work offline.

## Phase 6 - Live Mode

Scope:

- Add near-live polling through Concept2/ErgData-compatible sources when credentials are available.
- Provide a native demo live generator for QA and UI development.
- Keep live mode isolated from the later hardware transport layer.

Exit criteria:

- The native app can display an updating in-progress workout from a mock source.
- Polling failures, empty states, and recovery behavior are tested.

## Phase 7 - Hardware Connectivity

Scope:

- Evaluate Bluetooth FTMS and Concept2 PM connectivity after the core native app is stable.
- Treat hardware as an optional transport feeding the same live/replay model, not as a rewrite of analytics or storage.

Exit criteria:

- Transport capability matrix is documented.
- Bluetooth work begins only after privacy, replay, storage, and live-mode foundations are in place.

## Review Strategy

- Phase 0: direct commit to `main` to create the native scaffold.
- Phase 1 onward: one branch and pull request per phase.
- Phase PRs should include the relevant `.kiro/specs/phase-XX-*` updates, local validation commands, and a truthful scope statement.

