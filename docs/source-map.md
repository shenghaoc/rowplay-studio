# Web To Native Source Map

This file records the first mapping from the existing rowplay web repository to the native app.

**Web architecture baseline**: As of rowplay PR #166, the web app is
stateless with no KV/D1 storage. See web `.kiro/specs/remove-kv-d1/` for the
authoritative spec. Retired web surfaces are listed at the end of this file.

| Web Source | Native Target | Notes |
| --- | --- | --- |
| `src/lib/types.ts` | `Sources/RowPlayCore/Models` | Core Concept2 domain models are being ported as Swift value types. |
| `src/lib/format.ts` | `Sources/RowPlayCore/Support/RowPlayFormatting.swift` | Phase 0 ports time, pace, distance, challenge distance, and sport-specific watts; settings-wiring PR adds `DistanceUnit` and imperial formatting. |
| `src/lib/paceInput.ts` | `Sources/RowPlayCore/Support/PaceInput.swift` | Phase 1 ports pace string parsing and formatting. |
| `src/lib/datetime.ts` | `Sources/RowPlayCore/Support/RowPlayDateTime.swift` | Phase 1 ports logbook timestamp parsing, day-key arithmetic, and timezone-aware day resolution. |
| `src/lib/privacy.ts` | `Sources/RowPlayCore/Support/PrivacyRedaction.swift` | Phase 1 ports the share-link privacy guard (`isPubliclyShareable`). |
| `src/lib/analytics.ts` | `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Phase 0 ports summaries, distance bands, and linear trend; Phase 2 adds dashboard PB card and recent pace derivations. |
| `src/lib/analytics.ts` (PBs) | `Sources/RowPlayCore/Analytics/PersonalBests.swift` | Phase 1 ports personal best detection at standard distances with ±2% tolerance. |
| `src/lib/performancePredictor.ts` | `Sources/RowPlayCore/Analytics/PerformancePredictor.swift` | Phase 1 ports Paul's Law predictions and prediction table with beaten/behind/untried status. |
| `src/lib/mockData.ts` | `Sources/RowPlayCore/Fixtures/DemoWorkoutLibrary.swift` | Phase 0 ports deterministic demo workouts to keep the native app explorable without Concept2 credentials. |
| `src/routes/dashboard` and dashboard components | `Sources/RowPlayStudio/Views/DashboardView.swift` | Phase 0 creates a native dashboard shell; Phase 2 adds PB highlights, sport summaries, and query-driven filtering. |
| `src/lib/workoutQuery.ts` | `Sources/RowPlayCore/Library/WorkoutQuery.swift` | Phase 2 ports filter, sort, search, distance/duration chip toggling, PB-only filtering, and average power. |
| (new — no web equivalent) | `Sources/RowPlayCore/Library/WorkoutLibrarySource.swift` | Cache-backed library: enum tracking which data source (cache/demo/empty) the library loaded from. |
| (new — no web equivalent) | `Sources/RowPlayCore/Library/WorkoutLibrarySnapshot.swift` | Cache-backed library: immutable snapshot of loaded workout details and their source. |
| (new — no web equivalent) | `Sources/RowPlayCore/Library/WorkoutLibraryLoader.swift` | Cache-backed library: loads workouts from cache with demo-mode fallback, using batch detail retrieval; cache errors propagate without silent fallback. |
| `src/components/WorkoutListFilters.svelte` | `Sources/RowPlayStudio/Views/SidebarView.swift` + toolbar | Phase 2 adds sort menu and sport segmented picker to native sidebar/toolbar. |
| `src/lib/replay/engine.ts` | `Sources/RowPlayCore/Replay/ReplaySample.swift` + `ReplayState.swift` | Phase 3 ports `sampleAt`/`sampleIndexAt` interpolation and the `ReplayEngine` playback state machine. |
| `src/lib/replay/motion.ts` | `Sources/RowPlayCore/Replay/ReplayMotion.swift` | Phase 3 ports animation timing helpers: clampDt, dampFactor, warpStrokePhase, strokeSurge, catchEvents. |
| `src/lib/replay/comparabilityGuard.ts` | `Sources/RowPlayCore/Replay/ComparabilityGuard.swift` | Phase 3 ports axis classification and comparability predicate. |
| `src/lib/replay/ghostPick.ts` | `Sources/RowPlayCore/Replay/GhostPick.swift` | Phase 3 ports ghost candidate selection logic. |
| `src/lib/replay/sports.ts` | `Sources/RowPlayCore/Replay/ReplaySportTheme.swift` | Phase 3 ports sport labels and machine hex colors. |
| `src/lib/replay/inspector.ts` | `Sources/RowPlayCore/Replay/ReplayInspector.swift` | Phase 3 ports distancePerStroke and splitIndexAt. |
| `src/lib/analytics.ts` (durationBand) | `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Phase 3 adds `durationBand(for:)` for comparability guard. Duration-band parity fixture and direct tests at `Tests/RowPlayCoreTests/DurationBandParityTests.swift` with golden fixture at `Tests/RowPlayCoreTests/Fixtures/duration-band-parity.json`. |
| `src/routes/replay/[id]` (UI) | `Sources/RowPlayStudio/Views/ReplayView.swift` | Phase 3 adds SwiftUI Canvas replay surface with playback controls. |
| `src/lib/server/session.ts` (token handling) | `Sources/RowPlayCore/Sync/TokenStore.swift` | Phase 4 ports BYOT token storage to Keychain via `TokenStore` protocol (KeychainTokenStore + FakeTokenStore). |
| `src/lib/server/concept2.ts` (API client protocol) | `Sources/RowPlayCore/Sync/Concept2Client.swift` | Phase 4 defines `Concept2APIClient` protocol and `MockConcept2Client`; production URLSession implementation lives under `Sources/RowPlayCore/Concept2`. |
| `src/lib/server/db.ts` (workout cache) | `Sources/RowPlayCore/Sync/WorkoutCache.swift` | Phase 4 ports workout cache as async `WorkoutCache` protocol + `InMemoryWorkoutCache`; cache-backed library work adds `details(for:)` batch retrieval; SQLite foundation lives under `Sources/RowPlayCore/Storage`. **Note**: web `db.ts` was removed in PR #166. Native SQLite cache is a native-only local cache, not web D1 parity. |
| `src/lib/server/logger.ts` | `Sources/RowPlayCore/Support/PrivacySafeLogger.swift` | Phase 4 ports privacy-safe logging with `redact()` and `PrivacySafeLogger`. |
| `src/lib/server/data.ts` (sync state) | `Sources/RowPlayCore/Sync/SyncStateTracker.swift` | Phase 4 ports sync state tracking as `SyncState` + `SyncStateTracker` observable. **Note**: sync state logic was removed from web `data.ts` in PR #166. Native `SyncStateTracker` remains as native-local sync tracking. |
| `src/lib/analytics.ts` (comparison) | `Sources/RowPlayCore/Compare/WorkoutComparison.swift` | Phase 5 ports compareVerdict, sideStats, compareIntervalReps, and buildDistanceOverlay. |
| `src/lib/repComparison.ts` | `Sources/RowPlayCore/Compare/RepDetection.swift` | Phase 5 ports detectReps, repAvgPace, repsHaveHr, and rep series alignment. |
| `src/lib/server/export.ts` | `Sources/RowPlayCore/Export/WorkoutExport.swift` | Phase 5 ports CSV and JSON export formatting (TCX deferred). |
| `src/lib/hrImport.ts` | `Sources/RowPlayCore/Import/HrImport.swift` | Phase 5 ports HR interpolation, merge, and summarize logic. |
| `src/lib/types.ts` (Annotation) | `Sources/RowPlayCore/Annotations/Annotation.swift` | Phase 5 ports the Annotation model. |
| `src/routes/api/workouts/[id]/annotations` | `Sources/RowPlayCore/Annotations/AnnotationStore.swift` + `Sources/RowPlayCore/Annotations/SQLiteAnnotationStore.swift` | Phase 5 ports annotation store as async `AnnotationStore` protocol + `InMemoryAnnotationStore`. Phase 5 follow-up adds `SQLiteAnnotationStore` backed by a dedicated `annotations.sqlite` database. **Note**: web annotation API was retired in PR #166. Native annotations are a native-only feature. |
| `src/lib/server/share.ts` (redaction) | `Sources/RowPlayCore/Share/SharePackage.swift` | Phase 5 ports share package format with hardware metadata redaction. **Note**: web share API was removed in PR #166. Native share is a native-only local feature, not web parity. |
| `src/routes/compare/+page.svelte` | `Sources/RowPlayStudio/Views/WorkoutComparisonPanel.swift` | Phase 5 wires native compare selection, verdict, side stats, interval rows, and pace overlay on the workout detail surface. **Note**: web compare page was removed in PR #166. Native comparison is a native-only feature. |
| `src/routes/api/export` and `src/routes/api/export/[id]` | `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift` | Phase 5 wires current-workout CSV/JSON export through the native save panel. |
| `src/routes/api/workouts/[id]/hr-import` | `Sources/RowPlayStudio/Views/HrImportPanelView.swift` | Phase 5 wires offline HR sample-series import to the native detail view using the core merge engine. **Note**: web HR import API was retired (410) in PR #166. Native HR import is a native-only feature. |
| `src/components/AnnotationPanel.svelte` | `Sources/RowPlayStudio/Views/AnnotationPanelView.swift` | Phase 5 wires local annotation add/delete behavior to the native detail view. **Note**: web `AnnotationPanel.svelte` was deleted in PR #166. Native annotations are a native-only feature. |
| `src/routes/api/workouts/[id]/share` | `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift` | Phase 5 wires local share package save behavior without public URL generation. **Note**: web share API was retired (410) in PR #166. Native share is a native-only local feature. |
| `src/lib/liveMode.ts` (interval, backoff, stale) | `Sources/RowPlayCore/Live/LivePollingCadence.swift` | Phase 6 ports polling interval presets, effective interval, backoff computation, and staleness threshold. |
| `src/lib/liveMode.ts` + `liveMode.svelte.ts` (state) | `Sources/RowPlayCore/Live/LiveModeState.swift` | Phase 6 ports the live-mode state machine as a pure value type with explicit transition events. |
| `src/lib/liveMode.svelte.ts` (polling) | `Sources/RowPlayCore/Live/LiveSource.swift` | Phase 6 defines the injectable `LiveSource` protocol and `LivePollResult` model. |
| `src/routes/api/live/mock/+server.ts` | `Sources/RowPlayCore/Live/MockLiveSource.swift` | Phase 6 ports mock workout generation as an actor-based `LiveSource` implementation. |
| `src/lib/liveMode.svelte.ts` (demo samples) | `Sources/RowPlayCore/Live/DemoLiveSampleGenerator.swift` | Phase 6 adds sequential in-progress sample generation for UI development. |
| `src/components/LiveModePanel.svelte` | `Sources/RowPlayStudio/Views/LiveModePanelView.swift` | Phase 6 wires native live mode toggle, interval chips, and polling status to the dashboard. |
| (new — no web equivalent) | `Sources/RowPlayCore/Connectivity/ErgDevice.swift` | Phase 7 defines the ergometer device value type with stable id, display name, sport, and connection kind. |
| (new — no web equivalent) | `Sources/RowPlayCore/Connectivity/ErgConnectionState.swift` | Phase 7 defines the connection lifecycle state enum with human-readable failure reasons. |
| (new — no web equivalent) | `Sources/RowPlayCore/Connectivity/ErgTelemetrySample.swift` | Phase 7 defines the live hardware telemetry sample model, field-compatible with Stroke and LiveWorkoutSample. |
| (new — no web equivalent) | `Sources/RowPlayCore/Connectivity/ErgConnection.swift` | Phase 7 defines the injectable ergometer connection protocol boundary. |
| (new — no web equivalent) | `Sources/RowPlayCore/Connectivity/MockErgConnection.swift` | Phase 7 provides a deterministic mock hardware connection for testing and UI development. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Views/SettingsView.swift` | Phase 7 shows a mock-only hardware status row; settings-wiring PR connects controls to shared `AppPreferences`; sync coordinator PR adds Concept2 token save/sync/disconnect controls. |
| (new — no web equivalent) | `Sources/RowPlayStudio/App/RowPlayStudioApp.swift` | Phase 0 creates the `@main` app entry point with `WindowGroup`, `Settings` scene, and app delegate. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Stores/WorkoutLibrary.swift` | Phase 0 creates the central `@MainActor ObservableObject` app state store; settings-wiring PR adds `isEmpty` and `clearData()`. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Views/ContentView.swift` | Phase 0 creates the root `NavigationSplitView` container with toolbar sport picker and searchable modifier. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Views/MetricTile.swift` | Phase 0 creates a reusable metric tile component for dashboard and detail views. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Views/WorkoutDetailView.swift` | Phase 0 creates the workout detail surface; Phase 3 adds replay navigation. |
| (new — no web equivalent) | `Sources/RowPlayStudio/Views/WorkoutToolsView.swift` | Phase 5 creates the composition surface for workout tools (compare, export, HR import, annotations). |
| (new — no web equivalent) | `Sources/RowPlayStudio/Stores/AppPreferences.swift` | Settings wiring PR centralizes `demoModeEnabled`, `reduceReplayMotion`, and `preferredDistanceUnit` as a shared observable. |
| (new — no web equivalent) | `Sources/RowPlayCore/Models/DistanceUnit.swift` | Settings wiring PR adds `DistanceUnit` enum (`metric`/`imperial`) for distance formatting. |
| `src/lib/server/db.ts` (SQLite cache) | `Sources/RowPlayCore/Storage/SQLiteWorkoutCache.swift` | Native-only local cache, not web D1 parity. Stores `WorkoutDetail` JSON in a v1 schema with migration support and batch `details(for:)` reads. Web `db.ts` was removed in PR #166. |
| `src/lib/server/db.ts` (errors) | `Sources/RowPlayCore/Storage/WorkoutCacheError.swift` | Native-only cache errors: open, migration, query, encoding, decoding. |
| `src/lib/server/db.ts` (migrations) | `Sources/RowPlayCore/Storage/SQLiteWorkoutCacheMigration.swift` | Native-only schema migration using `PRAGMA user_version`. Web D1 migrations were removed in PR #166. |
| `src/lib/server/concept2.ts` (transport) | `Sources/RowPlayCore/Concept2/HTTPTransport.swift` | Injectable HTTP transport protocol + URLSession implementation. Tests use a fake transport; production uses `URLSessionHTTPTransport`. |
| `src/lib/server/concept2.ts` (endpoints) | `Sources/RowPlayCore/Concept2/Concept2Endpoint.swift` | Concept2 logbook API endpoint enum with deterministic URL construction matching web app routes. |
| `src/lib/server/concept2.ts` (errors) | `Sources/RowPlayCore/Concept2/Concept2Error.swift` | Typed Concept2 API errors with privacy-safe descriptions (no tokens, headers, or payloads in error text). |
| `src/lib/server/concept2.ts` (models) | `Sources/RowPlayCore/Concept2/Concept2Models.swift` | Minimal Codable response models for the Concept2 logbook API: workout summaries, detail, strokes, and splits. |
| `src/lib/server/concept2.ts` (mapping) | `Sources/RowPlayCore/Concept2/Concept2Mapper.swift` | Maps raw Concept2 API responses to domain types with unit normalization (tenths → seconds, decimetres → metres, bike pace divisor). |
| `src/lib/server/concept2.ts` (client) | `Sources/RowPlayCore/Concept2/URLSessionConcept2Client.swift` | URLSession-backed `Concept2APIClient` with BYOT token injection. Token is held in memory only, never persisted or logged. |
| `src/lib/server/data.ts` (sync) | `Sources/RowPlayCore/Sync/WorkoutSyncCoordinator.swift` | Sync coordinator foundation: pages through Concept2 summaries, fetches detail for each, and saves into `WorkoutCache`. Depends on protocols only, not concrete implementations. |
| `src/lib/server/data.ts` (sync result) | `Sources/RowPlayCore/Sync/WorkoutSyncResult.swift` | Value type reporting fetched/saved/failed counts and timestamps from a sync run. |
| `src/lib/server/data.ts` (sync errors) | `Sources/RowPlayCore/Sync/WorkoutSyncError.swift` | Typed sync errors with privacy-safe descriptions: client, cache, and mapping failures. |
| `src/lib/server/data.ts` + `src/lib/server/session.ts` (app sync flow) | `Sources/RowPlayStudio/Stores/Concept2SyncController.swift` | App-shell bridge that loads/saves BYOT tokens through `TokenStore`, creates `URLSessionConcept2Client`, syncs into `SQLiteWorkoutCache`, tracks `SyncStateTracker`, hydrates cached/demo/empty library state on launch without requiring a token, and reloads cache after sync. |
| `src/routes/settings` / account controls | `Sources/RowPlayStudio/Views/SettingsView.swift` + `Sources/RowPlayStudio/App/RowPlayStudioApp.swift` | Native Settings Concept2 section and Workout menu command for token save, sync, and disconnect. |
| (new — no web equivalent) | `Tests/RowPlayCoreTests/Integration/SyncPipelineIntegrationTests.swift` | Integration tests validating fake Concept2 data flows through `WorkoutSyncCoordinator` → `SQLiteWorkoutCache` → `WorkoutLibraryLoader`. Uses real temp SQLite databases; no real network calls. |
| `tests/fixtures/golden/*.fixture.json` | `Tests/RowPlayCoreTests/Fixtures/Concept2/` | Sanitized Concept2 golden fixtures copied from the web repo. Used by `Concept2FixtureDecodingTests` to validate native decoding/mapping parity and dynamically redaction-scan every bundled fixture. No real network calls or tokens. |
| `src/lib/server/concept2.golden.test.ts` | `Tests/RowPlayCoreTests/Concept2/Concept2FixtureDecodingTests.swift` | Native parity tests for Concept2 decoding/mapping against golden fixtures. Covers rower steady, rower interval, SkiErg, BikeErg, stroke monotonicity, and fixture redaction scanning. |
| (new — no web equivalent) | `Tests/RowPlayCoreTests/Concept2/Concept2AuthenticatedSmokeTests.swift` | Opt-in authenticated smoke tests for real Concept2 API validation. Skipped unless `ROWPLAY_CONCEPT2_TOKEN` is set. CI does not require credentials. Covers summary fetch, detail fetch, and token-redaction in errors. |

## Retired Web Surfaces

The following web files were removed or retired by rowplay PR #166. Native
equivalents (where they exist) are native-only features, not web parity
targets.

| Retired Web File | Reason |
| --- | --- |
| `src/lib/server/db.ts` | D1 workout cache removed; web is stateless. |
| `src/lib/server/detailCache.ts` | D1 detail cache removed. |
| `src/lib/server/historyWindow.ts` | Server history window removed. |
| `src/lib/server/share.ts` | Public share API removed. |
| `src/lib/server/leaderboard.ts` | Leaderboard logic removed. |
| `src/lib/server/rivalGhost.ts` | Server rival ghost removed. |
| `src/lib/server/hrImport.ts` | Server-persisted HR import removed. |
| `src/lib/server/syncState.test.ts` | Sync state tests removed with sync state. |
| `src/lib/leaderboard.ts` | Leaderboard helper removed. |
| `src/lib/mockLeaderboard.ts` | Mock leaderboard removed. |
| `src/lib/historyBackfill.ts` | History backfill removed. |
| `src/lib/replay/rivalGhost.ts` | Client rival ghost removed. |
| `src/routes/compare/+page.svelte` | Compare page removed. |
| `src/routes/leaderboard/+page.svelte` | Leaderboard page removed. |
| `src/routes/r/[token]/+page.svelte` | Public share page removed. |
| `src/components/AnnotationPanel.svelte` | Annotation panel removed. |
| `src/components/WorkoutTagBadge.svelte` | Workout tag badge removed. |
| `migrations/` (all files) | D1 migrations removed. |
| `wrangler.jsonc` (KV/D1 bindings) | KV/D1 bindings removed. |
