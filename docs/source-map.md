# Web To Native Source Map

This file records the first mapping from the existing rowplay web repository to the native app.

| Web Source | Native Target | Notes |
| --- | --- | --- |
| `src/lib/types.ts` | `Sources/RowPlayCore/Models` | Core Concept2 domain models are being ported as Swift value types. |
| `src/lib/format.ts` | `Sources/RowPlayCore/Support/RowPlayFormatting.swift` | Phase 0 ports time, pace, distance, challenge distance, and sport-specific watts. |
| `src/lib/paceInput.ts` | `Sources/RowPlayCore/Support/PaceInput.swift` | Phase 1 ports pace string parsing and formatting. |
| `src/lib/datetime.ts` | `Sources/RowPlayCore/Support/RowPlayDateTime.swift` | Phase 1 ports logbook timestamp parsing, day-key arithmetic, and timezone-aware day resolution. |
| `src/lib/privacy.ts` | `Sources/RowPlayCore/Support/PrivacyRedaction.swift` | Phase 1 ports the share-link privacy guard (`isPubliclyShareable`). |
| `src/lib/analytics.ts` | `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Phase 0 ports summaries, distance bands, and linear trend; Phase 2 adds dashboard PB card and recent pace derivations. |
| `src/lib/analytics.ts` (PBs) | `Sources/RowPlayCore/Analytics/PersonalBests.swift` | Phase 1 ports personal best detection at standard distances with ±2% tolerance. |
| `src/lib/performancePredictor.ts` | `Sources/RowPlayCore/Analytics/PerformancePredictor.swift` | Phase 1 ports Paul's Law predictions and prediction table with beaten/behind/untried status. |
| `src/lib/mockData.ts` | `Sources/RowPlayCore/Fixtures/DemoWorkoutLibrary.swift` | Phase 0 ports deterministic demo workouts to keep the native app explorable without Concept2 credentials. |
| `src/routes/dashboard` and dashboard components | `Sources/RowPlayStudio/Views/DashboardView.swift` | Phase 0 creates a native dashboard shell; Phase 2 adds PB highlights, sport summaries, and query-driven filtering. |
| `src/lib/workoutQuery.ts` | `Sources/RowPlayCore/Library/WorkoutQuery.swift` | Phase 2 ports filter, sort, search, distance/duration chip toggling, PB-only filtering, and average power. |
| `src/components/WorkoutListFilters.svelte` | `Sources/RowPlayStudio/Views/SidebarView.swift` + toolbar | Phase 2 adds sort menu and sport segmented picker to native sidebar/toolbar. |
| `src/lib/replay/engine.ts` | `Sources/RowPlayCore/Replay/ReplaySample.swift` + `ReplayState.swift` | Phase 3 ports `sampleAt`/`sampleIndexAt` interpolation and the `ReplayEngine` playback state machine. |
| `src/lib/replay/motion.ts` | `Sources/RowPlayCore/Replay/ReplayMotion.swift` | Phase 3 ports animation timing helpers: clampDt, dampFactor, warpStrokePhase, strokeSurge, catchEvents. |
| `src/lib/replay/comparabilityGuard.ts` | `Sources/RowPlayCore/Replay/ComparabilityGuard.swift` | Phase 3 ports axis classification and comparability predicate. |
| `src/lib/replay/ghostPick.ts` | `Sources/RowPlayCore/Replay/GhostPick.swift` | Phase 3 ports ghost candidate selection logic. |
| `src/lib/replay/sports.ts` | `Sources/RowPlayCore/Replay/ReplaySportTheme.swift` | Phase 3 ports sport labels and machine hex colors. |
| `src/lib/replay/inspector.ts` | `Sources/RowPlayCore/Replay/ReplayInspector.swift` | Phase 3 ports distancePerStroke and splitIndexAt. |
| `src/lib/analytics.ts` (durationBand) | `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Phase 3 adds `durationBand(for:)` for comparability guard. |
| `src/routes/replay/[id]` (UI) | `Sources/RowPlayStudio/Views/ReplayView.swift` | Phase 3 adds SwiftUI Canvas replay surface with playback controls. |
| `src/lib/server/session.ts` (token handling) | `Sources/RowPlayCore/Sync/TokenStore.swift` | Phase 4 ports BYOT token storage to Keychain via `TokenStore` protocol (KeychainTokenStore + FakeTokenStore). |
| `src/lib/server/concept2.ts` (API client) | `Sources/RowPlayCore/Sync/Concept2Client.swift` | Phase 4 defines `Concept2APIClient` protocol and `MockConcept2Client`; real URLSession client deferred to follow-up. |
| `src/lib/server/db.ts` (workout cache) | `Sources/RowPlayCore/Sync/WorkoutCache.swift` | Phase 4 ports workout cache as async `WorkoutCache` protocol + `InMemoryWorkoutCache`; SQLite deferred to follow-up. |
| `src/lib/server/logger.ts` | `Sources/RowPlayCore/Support/PrivacySafeLogger.swift` | Phase 4 ports privacy-safe logging with `redact()` and `PrivacySafeLogger`. |
| `src/lib/server/data.ts` (sync state) | `Sources/RowPlayCore/Sync/SyncStateTracker.swift` | Phase 4 ports sync state tracking as `SyncState` + `SyncStateTracker` observable. |
| `src/lib/analytics.ts` (comparison) | `Sources/RowPlayCore/Compare/WorkoutComparison.swift` | Phase 5 ports compareVerdict, sideStats, compareIntervalReps, and buildDistanceOverlay. |
| `src/lib/repComparison.ts` | `Sources/RowPlayCore/Compare/RepDetection.swift` | Phase 5 ports detectReps, repAvgPace, repsHaveHr, and rep series alignment. |
| `src/lib/server/export.ts` | `Sources/RowPlayCore/Export/WorkoutExport.swift` | Phase 5 ports CSV and JSON export formatting (TCX deferred). |
| `src/lib/hrImport.ts` | `Sources/RowPlayCore/Import/HrImport.swift` | Phase 5 ports HR interpolation, merge, and summarize logic. |
| `src/lib/types.ts` (Annotation) | `Sources/RowPlayCore/Annotations/Annotation.swift` | Phase 5 ports the Annotation model. |
| `src/routes/api/workouts/[id]/annotations` | `Sources/RowPlayCore/Annotations/AnnotationStore.swift` | Phase 5 ports annotation store as async `AnnotationStore` protocol + `InMemoryAnnotationStore`. |
| `src/lib/server/share.ts` (redaction) | `Sources/RowPlayCore/Share/SharePackage.swift` | Phase 5 ports share package format with hardware metadata redaction. |
| `src/routes/compare/+page.svelte` | `Sources/RowPlayStudio/Views/WorkoutComparisonPanel.swift` | Phase 5 wires native compare selection, verdict, side stats, interval rows, and pace overlay on the workout detail surface. |
| `src/routes/api/export` and `src/routes/api/export/[id]` | `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift` | Phase 5 wires current-workout CSV/JSON export through the native save panel. |
| `src/routes/api/workouts/[id]/hr-import` | `Sources/RowPlayStudio/Views/HrImportPanelView.swift` | Phase 5 wires offline HR sample-series import to the native detail view using the core merge engine. |
| `src/components/AnnotationPanel.svelte` | `Sources/RowPlayStudio/Views/AnnotationPanelView.swift` | Phase 5 wires local annotation add/delete behavior to the native detail view. |
| `src/routes/api/workouts/[id]/share` | `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift` | Phase 5 wires local share package save behavior without public URL generation. |
| `src/lib/liveMode.ts` (interval, backoff, stale) | `Sources/RowPlayCore/Live/LivePollingCadence.swift` | Phase 6 ports polling interval presets, effective interval, backoff computation, and staleness threshold. |
| `src/lib/liveMode.ts` + `liveMode.svelte.ts` (state) | `Sources/RowPlayCore/Live/LiveModeState.swift` | Phase 6 ports the live-mode state machine as a pure value type with explicit transition events. |
| `src/lib/liveMode.svelte.ts` (polling) | `Sources/RowPlayCore/Live/LiveSource.swift` | Phase 6 defines the injectable `LiveSource` protocol and `LivePollResult` model. |
| `src/routes/api/live/mock/+server.ts` | `Sources/RowPlayCore/Live/MockLiveSource.swift` | Phase 6 ports mock workout generation as an actor-based `LiveSource` implementation. |
| `src/lib/liveMode.svelte.ts` (demo samples) | `Sources/RowPlayCore/Live/DemoLiveSampleGenerator.swift` | Phase 6 adds sequential in-progress sample generation for UI development. |
| `src/components/LiveModePanel.svelte` | `Sources/RowPlayStudio/Views/LiveModePanelView.swift` | Phase 6 wires native live mode toggle, interval chips, and polling status to the dashboard. |
