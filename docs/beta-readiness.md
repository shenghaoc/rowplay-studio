# Beta Readiness

## Current State

RowPlay Studio has merged the native macOS foundation slices through Phase 7, the Phase 8A RealityKit foundation, Phase 8B articulated rigs, Phase 8C replay cameras and sport effects (PR #57), Phase 8D adaptive replay quality (PR #58), and Phase 10A past-session ghost replay (PR #61). Phase 10B complete rival workflow (constant pace, imported CSV/TCX/FIT rivals, finish verdict, local race report/card export) is implemented on branch `codex/phase-10b-complete-rival-workflow`.

### What Is Implemented

- **Domain models**: `Sport`, `Workout`, `Stroke`, `Split`, `WorkoutDetail` as Swift value types.
- **Analytics**: `WorkoutAnalytics` (summaries, distance/duration bands, trends), `PersonalBests` (standard-distance PB detection), `PerformancePredictor` (Paul's Law).
- **Query/filter/sort**: `WorkoutQuery` engine with sport, date, distance/duration chips, search, PB-only filtering, and multi-field sorting.
- **Replay engine**: Sampling (`sampleAt`/`sampleIndexAt`), motion timing, comparability guard, ghost selection, sport themes, inspector helpers, and a `ReplayState` playback state machine.
- **Replay renderer**: SwiftUI Canvas 2D replay surface with playback controls, scrubber, speed picker, and telemetry overlay.
- **Concept2 sync**: Settings saves a BYOT token through Keychain, `Workout > Sync Concept2 Logbook` and Settings run `WorkoutSyncCoordinator`, synced workouts persist through `SQLiteWorkoutCache`, the workout library loads cache/demo/empty state on launch without requiring a token, `SyncStateTracker` reports status, and disconnect clears token/cache/library data.
- **Workout tools**: Comparison (verdict, side stats, interval reps, distance overlay), rep detection, CSV/JSON export, HR import/merge, annotation model/store, and local share package.
- **Live mode**: State machine, polling cadence with backoff, `LiveSource` protocol, `MockLiveSource`, `DemoLiveSampleGenerator`, and a native live-mode panel.
- **Hardware connectivity**: `ErgDevice`, `ErgConnectionState`, `ErgTelemetrySample`, `ErgConnection` protocol, and `MockErgConnection` with deterministic telemetry.
- **3D replay foundation**: `ReplayStrokePose` (renderer-neutral pose model), `ReplayCourseLayout` (400m loop), `RealityReplaySceneView` (RealityKit scene), articulated sport rigs with joint hierarchies and contact invariants (RowErg, SkiErg, BikeErg), and a 2D/3D mode selector in replay view.
- **Phase 8C replay cameras and sport effects — merged as PR #57**: Renderer-neutral chase, side, overhead, and orbit camera solving; accessible 3D camera selection/reset and orbit gestures; fixed-capacity deterministic RowErg foam/blade-spray and SkiErg snow/pole-spray effects; lower-opacity ghost wakes; BikeErg effect suppression; and reduced-motion/seek resets. The unavailable trackpad-magnification, production-route ghost, and exact-1440x900 proof remains documented rather than rewritten as complete.
- **Phase 8D adaptive replay quality — merged as PR #58**: Persisted low, medium, high, and ultra quality ceilings with medium as the default; exact quality-specific course/effect entity budgets; calibrated sticky one-tier degradation with no automatic upgrade; raw-before-clamp sampling; stable inner-scene rebuilds; a bounded 120-sample metrics accumulator; and privacy-safe selection, degradation, and window telemetry. Available runtime evidence is recorded below without claiming universal or final production performance.
- **Phase 10A past-session ghost replay — merged as PR #61**: Ranked ghost candidate selection with user-visible rival picker; `ReplayRaceGap` live gap helpers (metres, seconds, absolute time, ghost sampling); `WorkoutLibrary` ghost candidate caching; 2D ghost stroke path on replay canvas; live ahead/behind gap display; 3D ghost pose integration with context clearing on rival change.
- **Phase 10B complete rival workflow — implementation complete on branch**: Generic `ReplayRival` for past-session, constant-pace, and imported CSV/TCX/FIT rivals; bounded file reads; streaming quoted CSV; strict namespace-insensitive TCX XML parsing; truncated-FIT rejection; `ReplayRaceResult` finish/winner/tie/DNF semantics with interpolated distance crossings; finish verdict UI; minimized local race report JSON and race-card PNG export/share without filenames or internal workout/session identifiers (no public URL); 2D/3D support for all rival kinds with fallback articulation for non-genuine traces.
- **Native shell**: `NavigationSplitView` layout, sidebar with sort/sport pickers, dashboard with metric tiles and PB highlights, workout detail with replay/tools, settings with mock-only hardware status.
- **Settings wiring**: `demoModeEnabled` controls demo data loading, `reduceReplayMotion` lowers replay animation frame rate, `preferredDistanceUnit` switches distance formatting between metric and imperial, `replayRenderQuality` persists the selected 3D ceiling with a medium fallback, and the Concept2 section manages token save/sync/disconnect. Effective quality and performance state are never persisted.
- **Demo mode**: Deterministic seeded workout data via `DemoWorkoutLibrary`; the app is fully explorable without Concept2 credentials.
- **Test suite**: the merged baseline and Phase 8C validation passed. Phase 8D adds focused coverage for exact tier budgets, governor calibration/degradation, bounded metrics, preferences, raw playback deltas, graph/effect counts, stable rebuilds, generation de-duplication, and accessibility. Phase 10A adds `ReplayRaceGapTests` (fixture parity and degenerate inputs), expanded `GhostPickTests` (ranked ordering, sanitizers, tie-break), `WorkoutLibraryGhostCandidateTests` (caching, exclusion, default selection), and `ReplayGhostWorkflowTests` (candidate construction and 2D ghost-path origins). The complete matrix passes with only the opt-in authenticated smoke tests skipped when no token is supplied.

## rowplay PR #166 Impact

rowplay PR #166 (`refactor: remove all KV and D1 dependencies`) removed
Cloudflare KV and D1 from the web app. Key implications for RowPlay Studio:

- **Web is stateless**: the web app no longer has server-side workout
  storage. Authenticated workout summaries and details are fetched live from
  Concept2 API per request.
- **Removed web features**: leaderboards, public shares, coaching
  annotations, server-persisted HR imports, manual tags, sync/backfill,
  comparison, and account-data deletion were removed from the web app.
- **Native SQLite is native-only**: `SQLiteWorkoutCache` remains a valid
  native-local/offline capability. It is not web D1 parity because D1 no
  longer exists in the web architecture.
- **Future sync must be careful**: native sync roadmap work should frame
  itself as native-local cache behavior, not as chasing removed web D1/KV
  architecture.
- **API validation**: future real API validation should test against the
  stateless Concept2 fetch behavior (live reads, no server cache).

## Verified

The items below describe the merged baseline, the validation completed for Phase 8C before PR #57 merged, and the Phase 8D evidence actually collected on that review branch. They do not claim unavailable visual or profiling cases passed.

- `swift test` — all tests pass with no failures.
- `swift build` — clean build.
- `git diff --check` — no whitespace errors.
- Phase 8C target matrix: `swift build --target RowPlayCore`, `swift test --filter RowPlayCoreTests`, `swift build --target RowPlayPlatform`, `swift test --filter RowPlayPlatformTests`, `swift test --filter RowPlayStudioTests`, full `swift test`, and full `swift build` all pass.
- Phase 8C architecture scans return no forbidden UI/platform imports from Core and no forbidden UI imports from Platform.
- Phase 8C bundle gates: `./script/build_and_run.sh --verify`, `--automation`, and `--sign-verify` pass; bundle verification reports an ad-hoc `com.shenghaoc.RowPlayStudio` signature and a valid `Info.plist`.
- Phase 8C visual evidence: RowErg, SkiErg, and BikeErg scenes; chase, side, overhead, and orbit cameras; orbit drag and double-click reset; pause/resume; backward/forward seeks; 2D fallback; automation/reduced-motion suppression; the 1000-point minimum-width layout; and the largest available 1307x768 window were inspected without control/text overlap. A visible RowErg wake was captured. Trackpad magnification, production-route ghost replay, and exact 1440x900 inspection were unavailable before PR #57 merged and are not retroactively claimed.
- Phase 8D focused tests and complete matrix pass: 876 Core tests with two expected authenticated-smoke skips, 56 Platform tests, and 81 Studio tests; full `swift test`, full `swift build`, and `git diff --check` also pass.
- Phase 8D architecture and bundle gates pass: both forbidden-import scans return no matches, and `./script/build_and_run.sh --verify`, `--automation`, and `--sign-verify` succeed with the valid ad-hoc `com.shenghaoc.RowPlayStudio` bundle.
- Phase 8D telemetry was captured from the staged app through the subsystem-scoped stream. It emitted bounded quality-selection and 120-sample window events only. Representative RowErg observations were low: 34.167 ms average/100.000 ms worst frame interval and 0.067/0.190 ms average/worst scene update; medium: 24.583/166.667 ms and 0.124/0.299 ms; ultra: 27.222/216.666 ms and 0.191/0.360 ms. The events exposed only tier, level, count, budget-comparison count, and timing numbers; no workout ID, account data, token, filename, or stroke value appeared. No degradation event was forced on the healthy machine.
- A post-review telemetry recheck on the rebased head captured a RowErg low window of 120 samples at 37.778/166.667 ms average/worst frame interval and 0.064/0.154 ms average/worst scene update with overBudget=35. The final schema omits a singular budgetMs field because each sample is compared with the active budget it observed.
- Phase 8D visual QA covered RowErg at all four tiers, SkiErg and BikeErg at low/ultra, chase/side/overhead/orbit, a quality change while playing with time/speed/camera continuity, pause/resume, forward/backward seek, automation/reduced-motion suppression, unchanged 2D, the 1000x732 minimum window, and the largest available 1308x768 window. Course density increased by tier; low and both BikeErg cases showed no effects; enabled RowErg/SkiErg effects remained restrained; no control/text overlap was observed.
- Phase 8D unavailable evidence is explicit: exact 1440x900, trackpad magnification, production-route ghost replay, and Instruments profiling were unavailable. Automated scene/governor tests cover bounded entities, ghost separation, and deterministic degradation, but do not replace those unavailable UI/profiling checks.
- Phase 10B validation on the ready-for-review branch passes all focused rival factory, parser, race-result, report, card, ghost-workflow, and 3D tests; `swift build --target RowPlayCore`; full `swift test` (928 tests, two expected authenticated-smoke skips); full `swift build`; both architecture scans; and `git diff --check`.
- Phase 10B staged-bundle gates pass with `./script/build_and_run.sh --verify`, `--automation`, and `--sign-verify`. The signed automation bundle was exercised through invalid and valid constant-pace selection, an actual CSV import via the native file panel, 2D and 3D rival rendering, finish/DNF verdict presentation, and real privacy-minimized race-report JSON and 1080x1440 race-card PNG saves. TCX/FIT import behavior is covered by parser tests rather than claimed as a separate native file-panel walkthrough.
- Source-map: all sync, storage, and app-shell wiring files have corresponding source-map entries.
- Roadmap: all phase status claims updated to reflect merged state.
- Privacy: `PrivacyRedaction` and `PrivacySafeLogger` are tested. No CoreBluetooth imports in `RowPlayCore`. Keychain uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Hardware scope: mock-only implementation; Settings correctly shows "Mock only" without real pairing or scanning controls.
- No stale test counts in task specs.
- Sync pipeline integration: `SyncPipelineIntegrationTests` validates fake Concept2 data flows through `WorkoutSyncCoordinator` → `SQLiteWorkoutCache` → `WorkoutLibraryLoader`. Real network sync still needs separate validation.
- Concept2 fixture decoding parity: `Concept2FixtureDecodingTests` validates native decoding/mapping against sanitized golden fixtures from the web repo (rower steady, rower interval, SkiErg, BikeErg) and redaction-scans every bundled fixture for credentials and PII. No real network calls.
- Authenticated Concept2 smoke tests: `Concept2AuthenticatedSmokeTests` validates real API request/response integration when `ROWPLAY_CONCEPT2_TOKEN` is set locally. Tests are skipped in CI. Token-redaction coverage ensures no credentials leak into error descriptions. Full production sync UX still needs separate QA.
- Computer Use readiness: the confirmed failing representation was the SwiftUI `GroupBox` used by workout-tool panels; `WorkoutToolSection` now provides an explicit semantic replacement with accessible headings and child controls. The normal staged app traverses successfully through dashboard and workout-detail charts, 2D/3D replay, back navigation, and cross-workout selection during replay. The bundle has a stable technical identity and verified ad-hoc signature, and `--automation` launches deterministic demo data with reduced replay motion. RowPlay does not request screen or audio permissions.

## Gaps Before Beta

### Must-Fix

1. **No real Bluetooth transport**: `ErgConnection` is protocol-only with a mock. CoreBluetooth transport is needed for real hardware connectivity.

### Should-Fix

1. **No FIT/TCX/GPX HR file parsing**: HR import accepts only JSON arrays or simple CSV; real HR files need format parsers. (Phase 10B adds FIT/TCX/CSV for **replay rivals only**, not general HR import.)
2. **Final production 3D performance is not proven**: Phase 8D's available automated, bundle, telemetry, and visual evidence passes, but exact 1440x900, trackpad magnification, production-route ghost replay, and Instruments profiling were unavailable. Tier targets are scheduling policy, not guaranteed frame rates, and the observed windows do not establish a universal tier-performance ordering.
3. **3D assets remain procedural**: No imported USD/USDZ athlete or equipment assets exist. Phase 8C does not claim final production asset fidelity.

## Must Not Ship Yet

- **Real Bluetooth/CoreBluetooth**: No entitlements, no permission strings, no background sessions. The mock boundary is correct for this stage.
- **Public sharing**: Share packages must not generate public URLs or leak hardware-identifying metadata until a companion service exists with proper privacy review.
- **OAuth flow**: BYOT only. OAuth requires a registered Concept2 app and security review.

## Recommended Next PRs

1. **CoreBluetooth erg transport**: Implement `CoreBluetoothErgConnection` conforming to `ErgConnection` with proper entitlements and permission handling.
