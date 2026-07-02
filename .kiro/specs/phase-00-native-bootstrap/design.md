# Phase 00 Native Bootstrap Design

## Architecture

Phase 0 creates two targets:

- `RowPlayCore`: domain models, deterministic demo data, formatting, and pure analytics.
- `RowPlayStudio`: SwiftUI macOS shell, app state, sidebar, dashboard, detail views, and settings.

The split keeps future iOS and test work viable. Native views read already-computed domain values and should not become the owner of analytics logic.

## Scene Model

The app uses a `WindowGroup("RowPlay Studio", id: "main")` so the primary window appears at launch. A `Settings` scene owns durable preferences. The app delegate activates regular Dock behavior because SwiftPM GUI apps are launched from a staged local bundle during development.

## UI Shape

The Phase 0 UI uses:

- `NavigationSplitView` for a macOS sidebar/detail layout.
- Sidebar `List` for workout selection.
- Toolbar segmented sport filter and reload command.
- `Charts` for early dashboard and stroke telemetry visualization.
- Settings form for scaffold-level preferences.

## Data Shape

Demo data is based on the web app's deterministic fixtures:

- `Sport`
- `Workout`
- `Stroke`
- `Split`
- `WorkoutDetail`

Phase 0 ports enough fields to support native dashboard/detail display. Full Concept2 payload parity is Phase 1 and Phase 4 work.

## Validation

Phase 0 validates through `swift test`, `swift build`, and `./script/build_and_run.sh --verify`.

