# UI Redesign and Design System Requirements

## R1: Central Design System

- **R1.1** `RowPlayStudio` owns a single `AppDesign` namespace for adaptive semantic colors, spacing, radii, typography, chart sizing, and shared surface treatments.
- **R1.2** Semantic metric colors remain stable across dashboard, detail, comparison, replay, and live-mode surfaces: distance, duration, pace, power, cadence, and heart rate retain distinct roles.
- **R1.3** Light and dark appearances use adaptive system colors without introducing Core or Platform UI dependencies.
- **R1.4** Repeated panel styling is implemented once through a reusable Studio-layer modifier.

## R2: Native macOS Information Hierarchy

- **R2.1** The app continues to use `NavigationSplitView`, native toolbar controls, native menus, disclosure controls, settings, importers, exporters, alerts, and confirmation dialogs.
- **R2.2** The dashboard prioritizes summary metrics, personal bests, distance by sport, and recent pace with a consistent hierarchy.
- **R2.3** Workout detail prioritizes the workout header, metric strip, separate pace and power charts, split boundaries, and split table before secondary tools.
- **R2.4** Workout tools remain reachable in one native disclosure group without duplicating export, HR import, comparison, or annotation systems.
- **R2.5** Replay remains reachable from workout detail and keeps one shared playback clock and one shared control surface for 2D and 3D renderers.
- **R2.6** Replay's cached 2D stroke path and sport theme refresh when canvas size, color scheme, or selected workout identity changes.

## R3: Loading, Empty, Error, and Repeated-Use States

- **R3.1** Cache loads and Concept2 syncs expose a single loading state used by the shell to present a stable, realistic redacted dashboard skeleton.
- **R3.2** While a library load or sync is active, repeat reload/sync/disconnect actions are disabled or rejected so concurrent operations cannot clear the loading state early.
- **R3.3** The empty library state explains both useful recovery paths: enable Demo Mode or open Settings to connect Concept2.
- **R3.4** Live-mode warnings use the caution color, while polling errors use the alert color and actionable retry copy.
- **R3.5** File import/export errors use native alerts with descriptive titles and dismiss actions.
- **R3.6** Deterministic automation mode expands workout tools by default so the full secondary flow can be inspected without changing the production default.

## R4: Accessibility and Motion

- **R4.1** Metric tiles, metric strips, telemetry groups, chart summaries, and sidebar workout rows expose explicit accessibility labels and values.
- **R4.2** Decorative separators and icons are hidden from assistive technology where they do not add meaning.
- **R4.3** Custom controls preserve native keyboard and focus behavior and expose labels, hints, or help where appropriate.
- **R4.4** Repeating empty-state motion is disabled when Reduce Motion is active; existing replay reduced-motion behavior remains intact.
- **R4.5** Color is never the only signal for review-relevant states; labels, icons, position, or copy carry the same meaning.

## R5: Data Accuracy and Performance

- **R5.1** Pace uses pace formatting and `/500m` semantics wherever it is presented as pace.
- **R5.2** Detail charts follow the active metric or imperial distance unit, including axis labels and split boundaries.
- **R5.3** Detail pace and power use separate scales so one metric cannot visually flatten the other.
- **R5.4** Expensive stroke chart derivations run only when workout identity, detail revision, or distance unit changes; chart samples are capped at 500 while retaining both endpoints.
- **R5.5** Dashboard accessibility summaries and chart domains always reflect current filters and units rather than stale view state.
- **R5.6** Split boundary marks use positional identities so zero-distance rest intervals cannot collapse duplicate boundaries.
- **R5.7** Comparison pace charts use a bounded pace domain, plot faster pace higher, follow the selected distance unit, and expose an aggregate accessibility summary.
- **R5.8** Derived power text rejects invalid or physically unrealistic values before integer conversion.

## R6: Architecture

- **R6.1** `RowPlayCore` remains unchanged by the redesign and contains no UI dependencies.
- **R6.2** `RowPlayPlatform` owns only the non-UI loading state needed to coordinate cache/sync operations.
- **R6.3** `RowPlayStudio` owns all design tokens, SwiftUI components, Charts code, native file presentation, and accessibility modifiers.
- **R6.4** Stroke-chart rendering and caching live in a focused `WorkoutStrokeAnalysisView` rather than expanding `WorkoutDetailView` into a chart coordinator.
- **R6.5** The package remains a macOS 26 SwiftPM application. Conditional non-macOS source guards do not claim or create a supported iPad product target.

## R7: Verification and Documentation

- **R7.1** Pure dashboard, power-formatting, and stroke-chart helpers have regression tests for invalid bounds, unit changes, changing inputs, downsampling, endpoints, and split transforms.
- **R7.2** Loading-state overlap behavior has a Platform regression test.
- **R7.3** `DESIGN.md`, `PRODUCT.md`, design QA evidence, this spec, and the PR body describe the final implementation without stale scope or test counts.
- **R7.4** The final gate runs `swift test`, `swift build`, `git diff --check`, and `./script/build_and_run.sh --verify`, followed by a fresh staged-app UI inspection.

## R8: Non-Goals

- No Core analytics, storage schema, sync protocol, or replay-domain behavior changes.
- No new iPad product target or claim of iPad support.
- No new social, gamification, or challenge system.
- No replacement for the existing import, export, comparison, annotation, live-mode, or replay systems.
