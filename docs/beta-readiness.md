# Beta Readiness

## Current State

RowPlay Studio has merged the native macOS foundation slices through Phase 7. The Phase 0 scaffold and Phase 1–7 PRs are on `main`, while production sync, persistent annotation storage, and real hardware transport remain beta blockers below. The app is a functional offline/demo Concept2 logbook analytics and workout replay application built as a SwiftPM package (Swift 5.9+, macOS 14.0+) with zero external dependencies.

### What Is Implemented

- **Domain models**: `Sport`, `Workout`, `Stroke`, `Split`, `WorkoutDetail` as Swift value types.
- **Analytics**: `WorkoutAnalytics` (summaries, distance/duration bands, trends), `PersonalBests` (standard-distance PB detection), `PerformancePredictor` (Paul's Law).
- **Query/filter/sort**: `WorkoutQuery` engine with sport, date, distance/duration chips, search, PB-only filtering, and multi-field sorting.
- **Replay engine**: Sampling (`sampleAt`/`sampleIndexAt`), motion timing, comparability guard, ghost selection, sport themes, inspector helpers, and a `ReplayState` playback state machine.
- **Replay renderer**: SwiftUI Canvas 2D replay surface with playback controls, scrubber, speed picker, and telemetry overlay.
- **Sync boundaries**: `TokenStore` protocol (Keychain-backed), `Concept2APIClient` protocol (mock only), `WorkoutCache` protocol (in-memory + SQLite foundation), `SyncStateTracker`, and `PrivacySafeLogger` with tested redaction.
- **Workout tools**: Comparison (verdict, side stats, interval reps, distance overlay), rep detection, CSV/JSON export, HR import/merge, annotation model/store, and local share package.
- **Live mode**: State machine, polling cadence with backoff, `LiveSource` protocol, `MockLiveSource`, `DemoLiveSampleGenerator`, and a native live-mode panel.
- **Hardware connectivity**: `ErgDevice`, `ErgConnectionState`, `ErgTelemetrySample`, `ErgConnection` protocol, and `MockErgConnection` with deterministic telemetry.
- **Native shell**: `NavigationSplitView` layout, sidebar with sort/sport pickers, dashboard with metric tiles and PB highlights, workout detail with replay/tools, settings with mock-only hardware status.
- **Settings wiring**: `demoModeEnabled` controls demo data loading, `reduceReplayMotion` lowers replay animation frame rate, `preferredDistanceUnit` switches distance formatting between metric and imperial.
- **Demo mode**: Deterministic seeded workout data via `DemoWorkoutLibrary`; the app is fully explorable without Concept2 credentials.
- **Test suite**: all tests pass with no failures.

## Verified

- `swift test` — all tests pass with no failures.
- `swift build` — clean build.
- `git diff --check` — no whitespace errors.
- Source-map: all `RowPlayCore` files have corresponding source-map entries; 6 app-shell files added.
- Roadmap: all phase status claims updated to reflect merged state.
- Privacy: `PrivacyRedaction` and `PrivacySafeLogger` are tested. No CoreBluetooth imports in `RowPlayCore`. Keychain uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Hardware scope: mock-only implementation; Settings correctly shows "Mock only" without real pairing or scanning controls.
- No stale test counts in task specs.

## Gaps Before Beta

### Must-Fix

1. **No production Concept2 sync**: `Concept2APIClient` remains mock-only, and no URLSession client or app sync workflow writes remote Concept2 data into the local cache. `WorkoutCache` now has a SQLite foundation that stores `WorkoutDetail` JSON in a v1 schema, but sync integration is still future work.
2. **No real Bluetooth transport**: `ErgConnection` is protocol-only with a mock. CoreBluetooth transport is needed for real hardware connectivity.
3. **No persistent annotation storage**: `InMemoryAnnotationStore` loses data on restart. SQLite or Core Data backing is needed for annotations. (Workout cache now has a SQLite foundation via `SQLiteWorkoutCache`.)

### Should-Fix

4. **`WorkoutAnalytics.durationBand` has no direct tests**: Tested only indirectly through `ComparabilityGuard`.
5. **No TCX export**: Deferred from Phase 5; needed for round-trip with Concept2 ecosystem tools.
6. **No FIT/TCX/GPX HR file parsing**: HR import accepts only JSON arrays or simple CSV; real HR files need format parsers.
7. **No companion web share service**: Share packages are local-only; no public URL generation.

## Must Not Ship Yet

- **Real Bluetooth/CoreBluetooth**: No entitlements, no permission strings, no background sessions. The mock boundary is correct for this stage.
- **Production Concept2 sync**: The URLSession client and app sync workflow are follow-up work. Do not wire mock clients into a user-facing sync flow.
- **Public sharing**: Share packages must not generate public URLs or leak hardware-identifying metadata until a companion service exists with proper privacy review.
- **OAuth flow**: BYOT only. OAuth requires a registered Concept2 app and security review.

## Recommended Next PRs

1. **URLSession Concept2 client**: Implement `URLSessionConcept2Client` conforming to `Concept2APIClient` with BYOT token injection.
2. **CoreBluetooth erg transport**: Implement `CoreBluetoothErgConnection` conforming to `ErgConnection` with proper entitlements and permission handling.
