# RowPlay Studio

Native macOS port of rowplay — Concept2 logbook analytics and real-time workout replay for RowErg, SkiErg, and BikeErg athletes. SwiftPM package with a `RowPlayCore` library and `RowPlayStudio` SwiftUI app.

## Build, Test, and Run

```bash
swift test                  # Run all tests
swift build                 # Build the package
swift test --filter <name>  # Run a single test class or method (e.g. --filter WorkoutAnalyticsTests)
./script/build_and_run.sh   # Build, stage as .app bundle under dist/, and launch
./script/build_and_run.sh --verify   # Launch and verify process is running
./script/build_and_run.sh --logs     # Launch with live os_log stream
```

The run script stages a proper `.app` bundle under `dist/` — do not launch the raw SwiftPM binary for GUI verification.

CI runs `swift test` then `swift build` on macOS.

## Architecture

Two targets in one SwiftPM package:

- **RowPlayCore** — Pure domain logic. No SwiftUI, AppKit, or macOS-specific imports. Portable to iOS.
  - `Models/` — Value types: `Workout`, `Stroke`, `Split`, `WorkoutDetail`, `Sport`
  - `Analytics/` — Pure calculations: `WorkoutAnalytics`, `PersonalBests`, `PerformancePredictor`
  - `Replay/` — Playback engine: `ReplaySample`, `ReplayState`, `ReplayMotion`, `GhostPick`, `ComparabilityGuard`
  - `Sync/` — Concept2 integration boundaries: `TokenStore`, `Concept2APIClient`, `WorkoutCache`, `SyncStateTracker`
  - `Live/` — Live polling: `LiveSource`, `LiveModeState`, `LivePollingCadence`, `DemoLiveSampleGenerator`
  - `Connectivity/` — Hardware protocol boundaries: `ErgConnection`, `ErgDevice`, `ErgTelemetrySample`
  - `Compare/`, `Export/`, `Import/`, `Annotations/`, `Share/` — Workout tools
  - `Support/` — Formatting, date/time, pace parsing, privacy redaction
  - `Fixtures/` — `DemoWorkoutLibrary` with deterministic seeded data for offline demo mode

- **RowPlayStudio** — SwiftUI macOS app shell.
  - `App/` — `@main` entry with `WindowGroup`, `NavigationSplitView`, command menus, settings scene
  - `Stores/` — `WorkoutLibrary` (`@MainActor ObservableObject`) as the central app state
  - `Views/` — Dashboard, sidebar, workout detail, replay canvas, comparison panel, live mode panel

## Key Conventions

### Separation rule
Keep reusable math and data in `RowPlayCore`. Keep SwiftUI, AppKit, and macOS process behavior out of `RowPlayCore`. The core library must remain importable by a future iOS target.

### Dependency injection via protocols
External boundaries are defined as protocols in `RowPlayCore` with production and mock implementations:
- `TokenStore` → `KeychainTokenStore` (prod) / `FakeTokenStore` (tests)
- `Concept2APIClient` → mock exists, real URLSession client deferred
- `WorkoutCache` → `InMemoryWorkoutCache` (tests), SQLite deferred
- `AnnotationStore` → `InMemoryAnnotationStore`
- `LiveSource` → `MockLiveSource`
- `ErgConnection` → `MockErgConnection`

Mock classes are `@unchecked Sendable` and use `NSLock` for thread safety. Mock erg connections use manual `emitSample()` — no real timers.

### Performance: memoize expensive derived data
`WorkoutLibrary` caches `filteredWorkouts`, `summary`, `detailByID`, etc. in `didSet` observers of `@Published` properties. Do not compute O(N) or O(N log N) derivations inline in SwiftUI computed properties — they re-evaluate on every render cycle.

### Privacy invariants
- Concept2 tokens go to Keychain only — never UserDefaults, plain files, logs, or exported fixtures.
- `PrivacySafeLogger` and `redact()` are mandatory for any code that logs user data.
- Share packages strip hardware-identifying metadata.
- Input parsers (`PaceInput`, `RowPlayDateTime`) bound raw input length before regex to prevent ReDoS.

### Accessibility
For visual tiles or grouped metric displays, use `.accessibilityElement(children: .ignore)` with explicit `.accessibilityLabel()` and `.accessibilityValue()`. Hide decorative characters (like "·" separators) with `.accessibilityHidden(true)`.

### Domain model notes
- `Sport` enum: `.rower`, `.skierg`, `.bike`. Use `Sport.fromConcept2Type()` for API string mapping.
- `WorkoutDetail` bundles a `Workout` summary with its `[Stroke]` and `[Split]` arrays.
- Pace is stored as `TimeInterval` (seconds per 500m). BikeErg watts are divided by `bikeWattsFromNormalizedPaceDivisor` (8.0).
- `challengeDistance` halves BikeErg distance (matches Concept2 challenge rules).

### Demo mode
The app launches with `WorkoutLibrary.demo()` using `DemoWorkoutLibrary.details` — deterministic seeded workout data. Demo mode is first-class; the app must be fully explorable without a Concept2 token.

### Test fixtures and parity
Golden parity fixtures (JSON under `Tests/RowPlayCoreTests/Fixtures/`) verify native calculations match the web app's verified values. `ParityFixtureLoader` loads these. When porting a web helper, add a parity fixture and test.

### Roadmap phases
Development follows numbered phases (0–7) documented in `docs/roadmap.md`. Phase 0 was direct-to-main; Phase 1+ uses branches and PRs. Kiro specs under `.kiro/specs/phase-XX-*` define requirements, design, and tasks per phase. Lessons learned are logged in `.jules/` files.

### Web-to-native mapping
`docs/source-map.md` tracks the correspondence between the original SvelteKit/Cloudflare web codebase and native Swift targets. Reference it when porting new web features.
