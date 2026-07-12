# Computer Use Automation Readiness — Design

## Problem and Diagnosis

RowPlay Studio originally terminated the Computer Use helper during accessibility
tree traversal. A temporary, local isolation investigation proved that the
offending representation was SwiftUI's generated `GroupBox` accessibility
container in the workout tools—not Charts, Canvas, RealityKit, or the app
shell. The diagnostic modes were removed once that cause was confirmed, so the
shipped app retains its normal UI hierarchy rather than a permanent set of
feature-disabling launch switches.

The issue was not caused by missing accessibility labels, privacy permissions,
or screen/audio entitlements. RowPlay Studio does not request any of those
permissions.

## Remediation

`WorkoutToolSection` replaces the `GroupBox` containers in export/share, HR
import, comparison, and annotations panels. It supplies a visible VoiceOver
heading and a contained accessibility tree, preserving every child control for
both VoiceOver and Computer Use without the incompatible framework container.

Charts retain explicit semantic labels and values. Per-workout stroke metrics
used by the Stroke Timeline accessibility value are calculated by
`WorkoutAnalytics` and cached by `WorkoutLibrary` whenever its `details`
collection changes. Views receive the cached value, so SwiftUI render cycles do
not traverse a workout's strokes.

The comparison pace overlay is refreshed by one task keyed to the current and
selected workout IDs plus `WorkoutLibrary.detailsRevision`, a lightweight token
incremented whenever workout details change. Candidate alignment remains
ID-based, preserving the selected comparison across same-workout edits while
avoiding equality checks across stroke and split histories during view updates.

## Bundle and Automation Contract

The staged bundle uses a stable technical identity:

| Field | Value |
|---|---|
| `CFBundleExecutable` | `RowPlayStudio` |
| `CFBundleIdentifier` | `com.shenghaoc.RowPlayStudio` |
| `CFBundleName` | `RowPlayStudio` |
| `CFBundleDisplayName` | `RowPlay Studio` |

`build_and_run.sh` ad-hoc signs and strictly verifies that staged bundle before
launching it. `--automation` passes `ROWPLAY_AUTOMATION=1` through Launch
Services. `AppLaunchConfiguration` reads that value once at launch and then:

1. uses deterministic demo data;
2. skips the background Concept2 cache load; and
3. lowers replay motion without hiding any production surface.

The privacy-safe `automation-readiness` log records only app identity,
automation mode, and main-content presentation. It deliberately excludes
workout, account, and filesystem data.

## Verified Surface

Computer Use successfully traverses the normal staged app's dashboard and
workout-detail charts, 2D/3D replay, back navigation, and cross-workout
selection during replay. The full UI is therefore the only supported
automation surface; no diagnostic isolation mode ships in the app.

## File Changes

| File | Change |
|---|---|
| `Sources/RowPlayStudio/App/AppLaunchConfiguration.swift` | Launch-only automation configuration and environment value. |
| `Sources/RowPlayPlatform/WorkoutLibrary.swift` | Cache stroke summaries alongside other view-facing derived data. |
| `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Pure single-pass stroke-summary calculation. |
| `Sources/RowPlayStudio/Views/WorkoutToolSection.swift` | Explicit semantic replacement for incompatible `GroupBox` containers. |
| `Sources/RowPlayStudio/Views/WorkoutComparisonPanel.swift` | Coalesced selected-pair overlay refresh outside render evaluation. |
| `Tests/RowPlayStudioTests/WorkoutComparisonPanelTests.swift` | Comparison-selection regression coverage. |
| `script/build_and_run.sh` | Staged bundle assembly, signing, verification, and automation launch. |
