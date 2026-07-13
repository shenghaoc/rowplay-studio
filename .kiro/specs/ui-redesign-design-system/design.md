# UI Redesign and Design System Design

## Architecture

```text
RowPlayPlatform
└── Concept2SyncController.isLoading
    └── serializes cache/sync operations and drives shell loading state

RowPlayStudio
├── Views/DesignTokens.swift
│   ├── AppDesign semantic tokens
│   ├── adaptive light/dark colors
│   └── panelStyle()
├── Views/ContentView.swift
│   ├── native split-view shell
│   ├── stable demo-backed loading skeleton
│   └── actionable empty state
├── Views/DashboardView.swift
│   └── current-input chart domains and accessibility summaries
├── Views/WorkoutDetailView.swift
│   └── header, metric strip, split table, and tool disclosure
├── Views/WorkoutStrokeAnalysisView.swift
│   └── cached/downsampled pace and power charts
└── Existing focused views
    ├── Sidebar, Replay, Live Mode
    └── Export, HR Import, Compare, Annotations
```

Dependency direction remains `RowPlayStudio -> RowPlayPlatform -> RowPlayCore`. The redesign adds no Core changes and no UI framework import to Platform.

## Visual Language

- Use adaptive semantic colors instead of literal presentation colors at call sites.
- Reserve rounded hero typography for the primary dashboard metric value; use system headline, callout, caption, and monospaced numeric styles elsewhere.
- Prefer tonal system materials and low-opacity grouped surfaces over shadows, decorative gradients, or web-style chrome.
- Keep native macOS controls visually native. Custom styling is limited to data visualization and the replay play/pause control, which retains a plain button style and a 48-point target.

## Dashboard and Shell States

The shell passes deterministic `DemoWorkoutLibrary` summaries into a redacted dashboard while cache loading is active. This renders the same major sections as the loaded dashboard and prevents a large post-load layout shift. Sidebar and dashboard controls are disabled until the operation finishes.

`Concept2SyncController` treats cache loading and sync as one serialized activity. `canSync` is false while `isLoading` is true, and both entry points reject overlap before mutating state. Reload and disconnect UI uses the same source of truth.

In deterministic automation mode, workout tools start expanded so export, import, comparison, and annotation controls are present in the captured accessibility tree. Normal launches keep the native disclosure collapsed by default.

## Workout Analysis

`WorkoutDetailView` owns the page-level composition. `WorkoutStrokeAnalysisView` owns chart-specific state and rendering:

1. An identity combines workout ID, `detailsRevision`, and `DistanceUnit`.
2. Identity changes rebuild a cache containing at most 500 chart strokes, the pace domain, and converted split-boundary distances.
3. Pace and power render as separate stacked Charts with separate Y scales.
4. Pace values are negated only for plotting so faster values rise; axis labels format the absolute seconds per 500 metres.
5. Split marks are keyed by their enumerated position so equal cumulative distances remain distinct.

The comparison overlay applies the same pace orientation and bounded-domain rule as detail charts, converts distance to the selected unit, and groups the visual series into one concise accessibility element.

## Accessibility

- Read-only visual metric groups use `.accessibilityElement(children: .ignore)` with explicit label and value.
- Workout-tool containers use `.contain` so their headings and interactive children remain traversable.
- Charts expose concise aggregate descriptions; screenshots alone are not treated as proof of complete VoiceOver compliance.
- Reduce Motion disables the only new repeating symbol effect.

## Native File Workflows

SwiftUI `fileImporter` and `fileExporter` provide native document pickers while keeping parsing and export generation in the existing RowPlayCore helpers. Security-scoped import access is acquired only while the selected file is read.

## Testing Strategy

- Platform: prove overlapping cache loads are rejected and `isLoading`/`canSync` return to the correct values.
- Dashboard: prove accessibility summaries and pace domains change with units and input workouts.
- Workout analysis: prove 501-999+ strokes are capped correctly, first/last samples survive, and split boundaries follow the selected distance transform.
- Full gate: SwiftPM tests/build, whitespace check, staged app launch, and current-run visual inspection of dashboard, workout detail, and the tools/replay entry points.
