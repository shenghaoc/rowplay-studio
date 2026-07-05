# RowPlay Studio Native Roadmap

This roadmap ports rowplay from SvelteKit/Cloudflare to native macOS first while keeping the core library usable for a future iOS target. Phase 0 is committed directly to `main` to establish the scaffold. Phase 1 onward should use separate branches and pull requests.

## Phase 0 - Native Bootstrap

Status: merged to `main`.

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

Status: merged to `main` (PR #1).

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

Status: merged to `main` (PR #2).

## Phase 3 - Replay Engine And Native Renderer

Scope:

- Port replay sampling, motion timing, ghost selection, comparability guard, sport-specific semantics, and replay inspector logic.
- Implement a native SwiftUI Canvas replay first, then decide whether Metal/SceneKit is justified for 3D.
- Add playback controls, scrubber, speed control, synchronized telemetry charts, reduced-motion handling, and ghost racing.

Exit criteria:

- Replay can run from deterministic demo data without a network connection.
- Sampling and ghost selection match web fixtures.
- Rendering choices are validated with screenshots and performance measurements on macOS.

Status: merged to `main`.

## Phase 4 - Concept2 Sync, Privacy, And Local Storage

Status: foundation slice merged to `main` (PR #7); full production sync and persistent storage work remains in progress.

Scope:

- Foundation PR: add a Keychain-backed token store boundary, injectable Concept2 API client protocol, async workout cache abstraction, privacy-safe logging, and sync state tracking.
- Follow-up PRs: wire BYOT token entry UI, implement the URLSession Concept2 client, add persistent SQLite-backed workout cache, and connect the sync workflow to the app shell.
- Preserve rowplay's privacy invariant: tokens do not enter UserDefaults, plain files, logs, exported fixtures, or analytics payloads.
- Keep Cloudflare-specific KV/D1 assumptions out of native core.

Exit criteria:

- Foundation PR has tested safe boundaries for tokens, client injection, local cache, sync state, and redaction.
- Full phase completion requires a user to sync Concept2 workouts into a persistent native local cache.
- Disconnect/delete purges local cached data and Keychain token state.
- Privacy-sensitive logs are redacted and covered by tests.

## Phase 5 - Compare, Export, Share, And Annotations

Status: foundation slice merged to `main` (PR #8); persistent annotations, TCX export, full HR file parsing, and public sharing remain in progress.

Scope:

- Foundation PR: port compare verdict, side stats, interval comparison, distance overlay, rep detection, CSV/JSON export, HR import/merge, annotation model/store, and local share package format.
- Native wiring in this PR: add workout detail tools for comparison, CSV/JSON export, offline HR sample-series import, local annotations, and local share package save.
- Follow-up PRs: connect annotation storage to a persistent backend, add TCX export, add full FIT/TCX/GPX HR file parsing if needed, and implement companion web share service integration.
- Preserve rowplay's privacy invariant: share packages strip hardware-identifying metadata.

Exit criteria:

- Foundation PR has tested domain models for comparison, export, HR import, annotations, and share packages, plus native detail wiring for the safe local workflow slice.
- Full phase completion requires exported data to round-trip with the web app where formats overlap.
- Share behavior is explicit about which data becomes public.
- Annotation, comparison, export, local share, and HR sample import flows work offline.

## Phase 6 - Live Mode

Status: merged to `main`.

Scope:

- Add near-live polling through Concept2/ErgData-compatible sources when credentials are available.
- Provide a native demo live generator for QA and UI development.
- Keep live mode isolated from the later hardware transport layer.

Exit criteria:

- The native app can display an updating in-progress workout from a mock source.
- Polling failures, empty states, and recovery behavior are tested.

## Phase 7 - Hardware Connectivity

Status: foundation slice merged to `main` (PR #10); real Bluetooth, FTMS, and Concept2 PM transport work remains in progress.

Scope:

- Foundation PR: add hardware connection protocol boundary, device model, connection state machine, telemetry sample type, and deterministic mock connection.
- The app only exposes a mock-only Settings status row in this slice; it does not offer pairing or scanning.
- This PR does NOT implement real Bluetooth, real FTMS, or real Concept2 PM protocols.
- Follow-up PRs: implement CoreBluetooth transport, add FTMS parsing, add Concept2 PM protocol support, and wire hardware telemetry into the live/replay model.
- Hardware samples should feed the same live/replay data model from Phase 6.

Exit criteria:

- Foundation PR has tested safe boundaries for device discovery, connection lifecycle, and telemetry ingestion.
- Full phase completion requires a user to connect to a real ergometer and see live telemetry.
- Bluetooth work begins only after privacy, replay, storage, and live-mode foundations are in place.

## Review Strategy

- Phase 0: direct commit to `main` to create the native scaffold.
- Phase 1 onward: one branch and pull request per phase.
- Phase PRs should include the relevant `.kiro/specs/phase-XX-*` updates, local validation commands, and a truthful scope statement.
