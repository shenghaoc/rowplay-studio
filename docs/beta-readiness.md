# Beta Readiness

## Current State

RowPlay Studio has merged the native macOS foundation slices through Phase 7. The Phase 0 scaffold and Phase 1–7 PRs are on `main`, while real hardware transport remains a beta blocker below. The app is a functional offline/demo Concept2 logbook analytics and workout replay application built as a SwiftPM package (Swift 5.9+, macOS 14.0+) with zero external dependencies.

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
- **Native shell**: `NavigationSplitView` layout, sidebar with sort/sport pickers, dashboard with metric tiles and PB highlights, workout detail with replay/tools, settings with mock-only hardware status.
- **Settings wiring**: `demoModeEnabled` controls demo data loading, `reduceReplayMotion` lowers replay animation frame rate, `preferredDistanceUnit` switches distance formatting between metric and imperial, and the Concept2 section manages token save/sync/disconnect.
- **Demo mode**: Deterministic seeded workout data via `DemoWorkoutLibrary`; the app is fully explorable without Concept2 credentials.
- **Test suite**: all tests pass with no failures.

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

- `swift test` — all tests pass with no failures.
- `swift build` — clean build.
- `git diff --check` — no whitespace errors.
- Source-map: all sync, storage, and app-shell wiring files have corresponding source-map entries.
- Roadmap: all phase status claims updated to reflect merged state.
- Privacy: `PrivacyRedaction` and `PrivacySafeLogger` are tested. No CoreBluetooth imports in `RowPlayCore`. Keychain uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Hardware scope: mock-only implementation; Settings correctly shows "Mock only" without real pairing or scanning controls.
- No stale test counts in task specs.
- Sync pipeline integration: `SyncPipelineIntegrationTests` validates fake Concept2 data flows through `WorkoutSyncCoordinator` → `SQLiteWorkoutCache` → `WorkoutLibraryLoader`. Real network sync still needs separate validation.
- Concept2 fixture decoding parity: `Concept2FixtureDecodingTests` validates native decoding/mapping against sanitized golden fixtures from the web repo (rower steady, rower interval, SkiErg, BikeErg) and redaction-scans every bundled fixture for credentials and PII. No real network calls.
- Authenticated Concept2 smoke tests: `Concept2AuthenticatedSmokeTests` validates real API request/response integration when `ROWPLAY_CONCEPT2_TOKEN` is set locally. Tests are skipped in CI. Token-redaction coverage ensures no credentials leak into error descriptions. Full production sync UX still needs separate QA.

## Gaps Before Beta

### Must-Fix

1. **No real Bluetooth transport**: `ErgConnection` is protocol-only with a mock. CoreBluetooth transport is needed for real hardware connectivity.

### Should-Fix

1. **`WorkoutAnalytics.durationBand` has no direct tests**: Tested only indirectly through `ComparabilityGuard`.
2. **No TCX export**: Deferred from Phase 5; needed for round-trip with Concept2 ecosystem tools.
3. **No FIT/TCX/GPX HR file parsing**: HR import accepts only JSON arrays or simple CSV; real HR files need format parsers.

## Must Not Ship Yet

- **Real Bluetooth/CoreBluetooth**: No entitlements, no permission strings, no background sessions. The mock boundary is correct for this stage.
- **Public sharing**: Share packages must not generate public URLs or leak hardware-identifying metadata until a companion service exists with proper privacy review.
- **OAuth flow**: BYOT only. OAuth requires a registered Concept2 app and security review.

## Recommended Next PRs

1. **CoreBluetooth erg transport**: Implement `CoreBluetoothErgConnection` conforming to `ErgConnection` with proper entitlements and permission handling.
