# Beta Readiness

## Current State

RowPlay Studio has merged the native macOS foundation slices through Phase 7 plus the Phase 8A RealityKit foundation and Phase 8B articulated rigs. The current Phase 8C branch contains replay-camera and bounded sport-effect implementation and passes its automated build, test, architecture, staged-launch, automation, and signing gates. Its visual-QA matrix remains partial where the environment cannot synthesize trackpad magnification, expose a production ghost-replay route, or provide a 1440x900 desktop; the PR is not merge-ready until that evidence is resolved or its requirement is narrowed. Real hardware transport remains a beta blocker below. The app is a functional offline/demo Concept2 logbook analytics and workout replay application built as a SwiftPM package (Swift 6.3+, macOS 26.0+) with zero external dependencies.

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
- **Phase 8C branch implementation — automated validation complete, partial visual QA**: Renderer-neutral chase, side, overhead, and orbit camera solving; accessible 3D camera selection/reset and orbit gestures; fixed-capacity deterministic RowErg foam/blade-spray and SkiErg snow/pole-spray effects; lower-opacity ghost wakes; BikeErg effect suppression; and reduced-motion/seek resets. The PR remains not merge-ready because the full requested visual matrix was not available.
- **Native shell**: `NavigationSplitView` layout, sidebar with sort/sport pickers, dashboard with metric tiles and PB highlights, workout detail with replay/tools, settings with mock-only hardware status.
- **Settings wiring**: `demoModeEnabled` controls demo data loading, `reduceReplayMotion` lowers replay animation frame rate, `preferredDistanceUnit` switches distance formatting between metric and imperial, and the Concept2 section manages token save/sync/disconnect.
- **Demo mode**: Deterministic seeded workout data via `DemoWorkoutLibrary`; the app is fully explorable without Concept2 credentials.
- **Test suite**: the merged baseline and Phase 8C branch suites pass with no failures. The Phase 8C run executed 847 Core tests with two authenticated smoke tests skipped, 51 Platform tests, and 64 Studio tests; the complete visual-QA matrix remains pending for the unavailable cases above.

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

The items below describe the merged baseline plus validation actually completed on the current Phase 8C branch. They do not claim the unavailable Phase 8C visual cases passed.

- `swift test` — all tests pass with no failures.
- `swift build` — clean build.
- `git diff --check` — no whitespace errors.
- Phase 8C target matrix: `swift build --target RowPlayCore`, `swift test --filter RowPlayCoreTests`, `swift build --target RowPlayPlatform`, `swift test --filter RowPlayPlatformTests`, `swift test --filter RowPlayStudioTests`, full `swift test`, and full `swift build` all pass.
- Phase 8C architecture scans return no forbidden UI/platform imports from Core and no forbidden UI imports from Platform.
- Phase 8C bundle gates: `./script/build_and_run.sh --verify`, `--automation`, and `--sign-verify` pass; bundle verification reports an ad-hoc `com.shenghaoc.RowPlayStudio` signature and a valid `Info.plist`.
- Phase 8C visual evidence: RowErg, SkiErg, and BikeErg scenes; chase, side, overhead, and orbit cameras; orbit drag and double-click reset; pause/resume; backward/forward seeks; 2D fallback; automation/reduced-motion suppression; the 1000-point minimum-width layout; and the largest available 1307x768 window were inspected without control/text overlap. A visible RowErg wake was captured. Trackpad magnification, production-route ghost replay, and exact 1440x900 inspection were unavailable and are not claimed.
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

1. **No FIT/TCX/GPX HR file parsing**: HR import accepts only JSON arrays or simple CSV; real HR files need format parsers.
2. **Phase 8D performance work is not implemented**: Quality tiers, adaptive performance behavior, and extended profiling remain future work. Final production 3D performance has not been proven.
3. **3D assets remain procedural**: No imported USD/USDZ athlete or equipment assets exist. Phase 8C does not claim final production asset fidelity.

## Must Not Ship Yet

- **Real Bluetooth/CoreBluetooth**: No entitlements, no permission strings, no background sessions. The mock boundary is correct for this stage.
- **Public sharing**: Share packages must not generate public URLs or leak hardware-identifying metadata until a companion service exists with proper privacy review.
- **OAuth flow**: BYOT only. OAuth requires a registered Concept2 app and security review.

## Recommended Next PRs

1. **CoreBluetooth erg transport**: Implement `CoreBluetoothErgConnection` conforming to `ErgConnection` with proper entitlements and permission handling.
