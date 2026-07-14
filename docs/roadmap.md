# RowPlay Studio Native Roadmap

This roadmap ports rowplay from SvelteKit/Cloudflare to native macOS first while keeping the core library usable for a future iOS target. Phase 0 is committed directly to `main` to establish the scaffold. Phase 1 onward should use separate branches and pull requests.

## Web Architecture Baseline

As of rowplay PR #166 (`refactor: remove all KV and D1 dependencies`), the
web app is stateless with no KV/D1 workout cache:

- Authenticated workout summaries and details are fetched directly from the
  Concept2 Logbook API per request.
- Session identity, optional OAuth tokens, and home timezone are sealed in the
  AES-GCM httpOnly `rp_session` cookie; a personal Concept2 token is sealed
  separately in the httpOnly `rp_tok` cookie.
- Native local SQLite cache is a RowPlay Studio-specific capability for
  offline/native use, not web parity.
- Removed web features (leaderboards, public shares, coaching annotations,
  server-persisted HR imports, manual tags, sync/backfill, comparison, and
  account-data deletion) should not be presented as current parity targets.

See web `.kiro/specs/remove-kv-d1/` for the authoritative web architecture
spec.

## Native Architecture

The native app uses a three-layer architecture:

- **RowPlayCore** — Pure Swift domain logic with no platform dependencies. Importable by future iOS targets.
- **RowPlayPlatform** — macOS non-UI layer using Foundation and Combine. Contains state management (WorkoutLibrary), sync orchestration (Concept2SyncController), preferences (AppPreferences), and factories (AnnotationStoreFactory).
- **RowPlayStudio** — SwiftUI macOS UI layer. Contains `@main` entry and all Views.

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

Status: foundation slice merged to `main` (PR #7); SQLite workout cache foundation added; URLSession Concept2 client foundation added; sync coordinator and app-shell sync wiring added.

Scope:

- Foundation PR: add a Keychain-backed token store boundary, injectable Concept2 API client protocol, async workout cache abstraction, privacy-safe logging, and sync state tracking.
- SQLite cache PR: add `SQLiteWorkoutCache` with v1 schema, idempotent migrations, and round-trip tests. Stores `WorkoutDetail` JSON for dashboard/replay cache foundation.
- Sync coordinator/app wiring PR: add `WorkoutSyncCoordinator` that bridges `Concept2APIClient` to `WorkoutCache` with paging, detail fetch, partial failure handling, cancellation propagation, auth/rate-limit aborts, and privacy-safe error reporting. Wire Settings token save/sync/disconnect and `Workout > Sync Concept2 Logbook` through `Concept2SyncController`, `KeychainTokenStore`, `URLSessionConcept2Client`, `SQLiteWorkoutCache`, and `SyncStateTracker`.
- Preserve rowplay's privacy invariant: tokens do not enter UserDefaults, plain files, logs, exported fixtures, or analytics payloads.
- Keep Cloudflare-specific KV/D1 assumptions out of native core. Note: the
  web app itself no longer uses KV/D1 (see Web Architecture Baseline above);
  native SQLite cache is a native-local/offline capability, not web parity.

Exit criteria:

- Foundation PR has tested safe boundaries for tokens, client injection, local cache, sync state, and redaction.
- SQLite cache foundation provides persistent `WorkoutDetail` storage with tested migrations.
- A user can sync Concept2 workouts into a persistent native local cache via a real URLSession client.
- Disconnect/delete purges local cached data and Keychain token state.
- Privacy-sensitive logs are redacted and covered by tests.

## Phase 5 - Compare, Export, Share, And Annotations

Status: foundation slice merged to `main` (PR #8); persistent annotations merged. TCX export merged. Full HR file parsing remains in progress. Local share packages are a native-only capability; public sharing is not a current web-parity target.

Scope:

- Foundation PR: port compare verdict, side stats, interval comparison, distance overlay, rep detection, CSV/JSON export, HR import/merge, annotation model/store, and local share package format.
- Native wiring in this PR: add workout detail tools for comparison, CSV/JSON export, offline HR sample-series import, local annotations, and local share package save.
- Follow-up PRs: connect annotation storage to a persistent backend, add full FIT/TCX/GPX HR file parsing if needed.
- Note: comparison, leaderboards, public shares, coaching annotations, and server-persisted HR imports have been removed from the web app (PR #166). Native implementations of these features are native-only capabilities, not web parity targets.
- Preserve rowplay's privacy invariant: share packages strip hardware-identifying metadata.

Exit criteria:

- Foundation PR has tested domain models for comparison, export, HR import, annotations, and share packages, plus native detail wiring for the safe local workflow slice.
- Full phase completion requires exported data to round-trip with the web app where formats overlap.
- Local share-package behavior is explicit about the included and redacted data.
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

## Phase 8 - 3D Replay

### Phase 8A - RealityKit Replay Foundation

Status: merged to `main` (PR #47).

Scope:

- Add renderer-neutral `ReplayStrokePose` model in `RowPlayCore` ported from web `strokeModel.ts`: drive/recovery state, intensity, fatigue, amplitude, drive fraction per sport.
- Add renderer-neutral `ReplayCourseLayout` in `RowPlayCore`: 400-metre deterministic loop with position, tangent, heading, multiple-lap wrapping, and lane offsets.
- Add `ReplayRendererMode` enum (`.twoD` / `.threeD`) and `RealityReplaySceneView` in `RowPlayStudio`.
- Build a RealityKit `RealityView` scene with procedural 400m course, lane markings, start/finish marker, directional/fill lighting, and sport-specific low-poly procedural placeholders (RowErg hull/oars, SkiErg frame/poles, BikeErg frame/wheels).
- Drive live position, orientation, bob/surge, and articulated motion from `ReplayStrokePose`.
- Render optional ghost in a separate lane with translucent material.
- Fixed deterministic chase camera following the live participant.
- Respect reduced-motion preference: freeze body articulation and camera smoothing.
- 2D/3D segmented picker in `ReplayView`. Default to 3D with full existing 2D fallback.
- Parity fixture for web `strokePoseAt` outputs.
- New tests: `ReplayStrokePoseTests`, `ReplayCourseLayoutTests`, `ReplayRendererModeTests`.

Exit criteria:

- `swift test` passes with all new and regression tests.
- `swift build` passes.
- RealityKit 3D scene renders with visible course, athlete, and ghost placeholders.
- 2D/3D switching preserves all playback controls.
- No architecture violations (no Core/Platform imports of RealityKit).

Non-goals for Phase 8A:

- Final high-detail athlete rigs, imported USD/USDZ assets, skinning, inverse kinematics.
- Particles, water simulation, interactive orbit camera, quality presets.
- Metal shaders, SceneKit, Bluetooth, HR parsers, OAuth, public sharing.

### Phase 8B - Articulated Sport Rigs

Status: complete.

Scope:

- Add `ReplayRigPose.swift` in `RowPlayCore` with portable, deterministic rig-pose value types (`ReplayAthleteJointPose`, `RowerRigPose`, `SkiErgRigPose`, `BikeErgRigPose`, `ReplaySportRigPose`) and `ReplayRigPoseSolver`.
- Split Phase 8A placeholder `ReplaySportModels.swift` into focused files: `ReplaySportRig.swift` (protocol + factory), `ReplayAthleteRig.swift` (articulated body hierarchy), `ReplayRowerRig.swift`, `ReplaySkiErgRig.swift`, `ReplayBikeErgRig.swift`, `ReplayMeshFactory.swift` (reusable mesh/material helpers).
- Build articulated entity hierarchies with named pivots: pelvis → torso → shoulders → arms → hands; pelvis → thighs → shins → feet.
- Translate web `renderer3d.ts` avatar animation formulas: rower seat/handle/oar sweep, SkiErg crunch/pull, BikeErg crank/pedal/forward-kinesic leg tracking.
- Contact invariants: hands on handle/handlebar, feet at footplate/platform/pedals, pelvis on seat/saddle, oars pivot from gates.
- Ghost translucency applied recursively to every rig material.
- Reduced motion returns stable neutral pose.
- All solver inputs/outputs sanitized (no NaN/Infinity).
- Tests: `ReplayRigPoseTests` (Core), `ReplaySportRigStructureTests` (Studio).

Exit criteria:

- `swift test` passes with all new and regression tests.
- `swift build` passes.
- Architecture checks pass (no forbidden imports in Core/Platform).
- Articulated rigs replace Phase 8A placeholders.
- Contact points do not visibly separate during animation.
- Live and ghost rigs animate independently.

Non-goals for Phase 8B:

- Interactive orbit camera and camera presets.
- Quality tiers (low/medium/high/ultra).
- Water/snow surface effects, catch spray, wake trails.
- Imported USD/USDZ sport equipment assets.
- Performance governor and adaptive quality.

## Phase 9 - Computer Use Automation Readiness

Status: complete.

Scope:

- Wrap Charts views with `.accessibilityElement(children: .ignore)` and explicit semantic summaries for Computer Use compatibility.
- Harden staged bundle metadata: consistent CFBundleName/CFBundleDisplayName, ad-hoc signing, codesign verification.
- Add `--automation` launch mode in `build_and_run.sh` for deterministic Computer Use testing.
- Emit privacy-safe launch telemetry that distinguishes staged-app launch and visible-shell failures from helper-side accessibility failures.
- Add focused tests for automation mode and cached stroke summaries.
- Replace the incompatible workout-tool `GroupBox` AX representation with explicit semantic sections that preserve every child action.
- Cache per-workout stroke summaries in `WorkoutLibrary` so accessibility values never recompute stroke-derived metrics during SwiftUI renders.
- Update roadmap, beta-readiness, and source-map documentation.

Exit criteria:

- `swift test` passes with all new and regression tests.
- `swift build` passes.
- `./script/build_and_run.sh --verify` launches successfully.
- `./script/build_and_run.sh --automation` launches successfully.
- `codesign --verify --deep --strict dist/RowPlayStudio.app` passes.
- Computer Use can traverse the full production accessibility tree without crashing `SkyComputerUseService`.
- VoiceOver accessibility is preserved with meaningful names, values, and roles.

Non-goals:

- External dependencies.
- Modifying RunPlayStudio.
- Adding screen-recording, microphone, audio-capture, or private TCC entitlements.
- Altering macOS privacy settings or resetting TCC databases.
- Hiding meaningful UI from VoiceOver.
- Upgrading Swift, macOS deployment target, CI runners, or architecture layers.

### Phase 8C - Replay Cameras and Sport Effects

Status: merged to `main` (PR #57).

Scope:

- Add renderer-neutral camera models and finite deterministic target-pose solving in `RowPlayCore` for chase, side, overhead, and orbit presets.
- Add clamped orbit interaction, frame-rate-independent camera damping through `ReplayMotion.dampFactor(rate:dt:)`, a 46...51 degree speed-aware chase field of view, and fixed-FOV camera behavior under reduced motion.
- Add compact 3D-only camera selection and reset controls, plus orbit-only drag, trackpad magnification, and double-click reset without changing the replay clock or existing 2D/playback behavior.
- Add renderer-neutral sport-effect profiles, a fixed-capacity 48-droplet particle pool, deterministic catch-spray variation, and fixed-capacity 24-entry wake histories.
- Render a restrained RowErg foam wake and blade-tip catch spray, a SkiErg snow trail and pole-basket spray, no wake or spray for BikeErg, and an independent lower-opacity ghost wake.
- Reset transient effects on backward seeks, non-finite movement, jumps over 30 metres, scene identity changes, and reduced-motion/automation transitions. Paused frames preserve wake history and never emit catch spray.
- Prebuild every RealityKit effect entity, mesh, and material with the scene; per-frame updates change only bounded state, transforms, visibility, scale, and opacity.
- Add Linux-compatible Core camera/effect tests, macOS scene-effect tests, accessibility coverage, and synchronized roadmap/source-map/beta documentation.

Exit criteria:

- The complete SwiftPM build and test matrix passes without weakening existing replay, navigation, or rig assertions.
- Core and Platform architecture scans contain no forbidden framework imports.
- `./script/build_and_run.sh --verify`, `--automation`, and `--sign-verify` pass for the staged app bundle.
- Visual QA covers all three sports, all four cameras, orbit gestures/reset, seek behavior, ghost trails, reduced motion, 2D fallback, and supported window sizes; any unavailable proof is reported explicitly.

Branch validation:

- The full SwiftPM build/test matrix, whitespace check, architecture scans, staged launch, automation launch, and bundle-signature verification pass.
- Visual inspection covered all sport scenes, all camera presets, orbit drag and double-click reset, pause/resume, backward/forward seek, the 2D fallback, reduced-motion particle suppression, the 1000-point minimum-width layout, and the largest 1307x768 app window available in the validation environment. No control or text overlap was observed.
- Trackpad magnification was unavailable through the Computer Use bridge. Ghost replay was not reachable through the production navigation route because it never supplied `ghostDetail`; ghost separation, translucency, and independent wake state remained covered by scene tests. Exact 1440x900 inspection was unavailable on the 1307x768 validation desktop. PR #57 merged with these limits recorded; the merge does not retroactively establish the unavailable visual proof.

Non-goals for Phase 8C:

- Quality tiers, quality preferences, `PerfGovernor`, adaptive degradation, or final production performance claims.
- Imported USD/USDZ assets, custom shaders, Metal, SceneKit, or a second 3D renderer.
- External dependencies, hardware transport, toolchain/deployment-target changes, new timers, or unrelated UI redesign.

### Phase 8D - Adaptive Replay Quality and Performance Profiling

Status: implementation and the available validation matrix are complete on a focused draft branch; review is pending.

Scope:

- Add persisted low, medium, high, and ultra 3D quality ceilings, with medium as the default and corrupt-preference fallback.
- Configure exact, fixed RealityKit budgets per effective tier:

  | Tier | Course ring segments | Lane markers | Wake entries per participant | Spray particles | Spray droplets per side per catch | Timeline target |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | Low | 48 | 24 | 0 | 0 | 0 | 30 Hz |
  | Medium | 72 | 48 | 16 | 40 | 4 | 60 Hz |
  | High | 96 | 64 | 28 | 48 | 4 | 60 Hz |
  | Ultra | 144 | 96 | 44 | 72 | 6 | 60 Hz |

- Treat the selected tier as a ceiling. Calibrate from raw, unclamped playback-frame intervals, then degrade by one sticky step after sustained over-budget samples: ultra to high to medium to low, high to medium to low, medium to low, and low remains low. Adaptive quality never upgrades during a replay scene; a manual selection resets calibration and begins at the selected tier.
- Preserve the clamped delta for playback, camera, and effect motion while rejecting first-frame, paused, 2D, non-finite, non-positive, duplicate-generation, and app-background-sized performance samples.
- Rebuild only the inner RealityKit graph when effective quality changes, preserving replay time, playing state, speed, camera preset, and orbit state while clearing transient effects.
- Accumulate only scalar 120-sample performance windows and emit bounded unified-log events for quality selection, adaptive degradation, and completed windows. Telemetry contains public tier names, governor level, counts, and numeric timing measurements only; it excludes workout, account, token, filename, and stroke data and never logs per frame.
- Keep quality policy, the calibrated governor, and bounded metrics in `RowPlayCore`; preference persistence in `RowPlayPlatform`; and SwiftUI, RealityKit, and OSLog integration in `RowPlayStudio`.

Exit criteria:

- Focused and complete SwiftPM build/test matrices pass without weakening Phase 8C replay, camera, effect, rig, navigation, accessibility, or 2D assertions.
- Core and Platform architecture scans contain no forbidden imports.
- Staged launch, automation launch, and signature verification pass.
- Bounded telemetry is observed for a quality selection and completed metrics windows, with no sensitive fields or per-frame logging.
- Required sport/tier/camera, quality-transition, seek, reduced-motion, 2D, and window-size visual checks are completed, with measured observations and unavailable checks reported explicitly.

Validation status:

- Focused tests and the complete SwiftPM matrix pass: 876 Core tests with the two expected authenticated-smoke skips, 56 Platform tests, and 81 Studio tests. Core and Platform forbidden-import scans returned no matches, `git diff --check` passed, and the staged `--verify`, `--automation`, and `--sign-verify` bundle gates passed.
- The live `replay-performance` stream emitted bounded quality-selection and 120-sample window events. Representative RowErg observations from this machine were: low 34.167 ms average/100.000 ms worst frame interval and 0.067/0.190 ms average/worst scene update; medium 24.583/166.667 ms and 0.124/0.299 ms; ultra 27.222/216.666 ms and 0.191/0.360 ms. These measurements do not establish a universal tier-performance ordering.
- A rebased-head schema recheck captured another RowErg low window: 120 samples, 37.778/166.667 ms average/worst frame interval, 0.064/0.154 ms average/worst scene update, and overBudget=35. The final event deliberately omits one budgetMs value because the window uses per-sample active budgets.
- Visual QA covered RowErg low/medium/high/ultra, SkiErg low/ultra, BikeErg low/ultra, all camera presets, a live quality change, pause/resume, forward/backward seek, automation/reduced-motion suppression, unchanged 2D mode, the 1000x732 minimum window, and the largest available 1308x768 window without control/text overlap. Low showed no effects and BikeErg showed no effects at either inspected tier; enabled effects remained restrained.
- Exact 1440x900 inspection, trackpad magnification, production-route ghost replay, and Instruments profiling were unavailable. No degradation event was forced on the healthy machine; deterministic governor tests provide that proof.
- No guaranteed frame rate, benchmark improvement, GPU resolution scaling, imported production asset, or final production-performance claim is made by the tier targets above.

## Review Strategy

- Phase 0: direct commit to `main` to create the native scaffold.
- Phase 1 onward: one branch and pull request per phase.
- Phase PRs should include the relevant `.kiro/specs/phase-XX-*` updates, local validation commands, and a truthful scope statement.
