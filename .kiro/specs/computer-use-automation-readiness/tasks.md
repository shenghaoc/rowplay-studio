# Computer Use Automation Readiness — Tasks

## Task 1: Create IsolationConfig infrastructure

- [x] Create `Sources/RowPlayStudio/App/IsolationConfig.swift`
- [x] Define `IsolationConfig` struct with `IsolationLevel` enum
- [x] Read `ROWPLAY_ISOLATION_LEVEL` from `ProcessInfo.processInfo.environment`
- [x] Read `ROWPLAY_AUTOMATION` from environment
- [x] Pass config through SwiftUI environment
- [x] Update `RowPlayStudioApp.swift` to inject config

## Task 2: Wire isolation into views

- [x] Update `DashboardView` to conditionally render charts based on config
- [x] Update `WorkoutDetailView` to conditionally render chart/replay based on config
- [x] Update `ContentView` to conditionally render detail based on config
- [x] Update `ReplayView` to conditionally render 3D/Canvas based on config
- [x] Run the isolation matrix through Computer Use and record the confirmed offending AX element

## Task 3: Add accessibility summaries for Charts

- [x] Wrap `DashboardView` Distance by Sport chart with accessibility summary
- [x] Wrap `DashboardView` Recent Pace chart with accessibility summary
- [x] Wrap `WorkoutDetailView` Stroke Timeline chart with accessibility summary
- [x] Ensure all charts use `.accessibilityElement(children: .ignore)` with explicit label/value
- [x] Confirm the retained semantic summaries resolve the observed helper failure

## Task 4: Bundle metadata hardening

- [x] Update `build_and_run.sh` Info.plist: CFBundleName = RowPlayStudio
- [x] Add CFBundleDisplayName = RowPlay Studio
- [x] Add ad-hoc codesign after bundle assembly
- [x] Add codesign verification step
- [x] Add `--automation` mode to build script
- [x] Add `--isolation LEVEL` mode so each isolation level reaches the staged bundle

## Task 5: Add automation launch support

- [x] Read `ROWPLAY_AUTOMATION` environment variable in app
- [x] When set: force demo mode, disable sync, reduce motion
- [x] Ensure automation mode uses full production UI (not isolation modes)

## Task 6: Add focused tests

- [x] Create `Tests/RowPlayStudioTests/ComputerUseAutomationReadinessTests.swift`
- [x] Test `IsolationConfig` default values
- [x] Test `IsolationConfig` with environment overrides
- [x] Test automation mode configuration
- [x] Test environment-backed isolation parsing and invalid-level fallback

## Task 7: Update documentation

- [x] Update `docs/roadmap.md` with computer-use-automation-readiness phase
- [x] Update `docs/beta-readiness.md` with verification status
- [x] Update `docs/source-map.md` with new file entries

## Task 8: Validate

- [x] `swift test` passes
- [x] `swift build` passes
- [x] `git diff --check` passes
- [x] `./script/build_and_run.sh --verify` launches
- [x] `./script/build_and_run.sh --automation` launches
- [x] `plutil -lint dist/RowPlayStudio.app/Contents/Info.plist` passes
- [x] `codesign --verify --deep --strict dist/RowPlayStudio.app` passes
- [x] Computer Use returns semantic state and remains running for the full surface
