# Computer Use Automation Readiness — Design

## Problem Statement

RowPlayStudio crashes the Computer Use helper (`SkyComputerUseService`) with
`EXC_BREAKPOINT` / `SIGTRAP` when the helper attempts to traverse the
accessibility tree. The crash signature is:

```
exception: EXC_BREAKPOINT, signal: SIGTRAP
termination: Trace/BPT trap: 5
faultingThread: 4 (com.apple.root.user-initiated-qos.cooperative)
```

RunPlayStudio, a similar SwiftUI macOS app, works correctly with Computer Use
on the same machine. The difference is in RowPlayStudio's UI complexity:
Charts views, RealityKit 3D scenes, and custom Canvas replay surfaces.

## Root Cause Hypothesis

SwiftUI Charts and RealityKit views generate framework-level accessibility
elements that Computer Use's `TransformedUIElement` transformer cannot process.
When the helper encounters an incompatible AX role, representation, or deeply
nested hierarchy, it hits an internal assertion (`AccessibilitySupport.UIElementError`)
and crashes with SIGTRAP.

The crash is NOT caused by:
- Missing accessibility labels (these would cause silent failures, not crashes)
- Permission differences (both apps use the same TCC path)
- Audio/screen recording entitlements (neither app requests them)

## Progressive Isolation Strategy

### Isolation Mechanism

Add a `ROWPLAY_ISOLATION_LEVEL` environment variable read at app launch through
`ProcessInfo.processInfo.environment`. This controls which UI sections render:

| Level | Charts | RealityKit | Canvas Replay | Detail Sections | State |
|---|---|---|---|---|---|
| `full` | enabled | enabled | enabled | all | production default |
| `no_charts` | disabled | enabled | enabled | all | tests Charts as offender |
| `no_replay3d` | enabled | disabled | enabled | all | tests RealityKit |
| `no_replay` | enabled | disabled | disabled | all | tests any replay |
| `sidebar_only` | disabled | disabled | disabled | none | minimal NavigationSplitView |
| `minimal` | disabled | disabled | disabled | none | bare WindowGroup |

The isolation is implemented through a single `IsolationConfig` struct in
`RowPlayStudio/App/IsolationConfig.swift` read once at launch and passed through
the environment. Views check `config.chartsEnabled`, `config.replay3DEnabled`,
etc. before rendering the corresponding section.

### Isolation Binary Search Order

1. Start at `full` — confirm crash reproduces
2. Try `no_charts` — if this fixes it, Charts is the offender
3. Try `no_replay3d` — if this fixes it, RealityKit is the offender
4. Try `no_replay` — narrows to replay surfaces
5. Try `sidebar_only` — confirms the basic shell works

### Safety

- `IsolationConfig` lives in `RowPlayStudio` only (not Core or Platform)
- Defaults to `.full` — zero behavior change for normal launches
- The `--automation` flag sets `no_charts` + demo mode (see below)
- Temporary probes are removed after diagnosis; only the final config remains

## Remediation Plan

After identifying the offender, apply the minimum fix:

### If Charts is the offender

Every `Chart` view already uses standard SwiftUI accessibility. The fix is to
wrap each Chart in `.accessibilityElement(children: .ignore)` with an explicit
`.accessibilityLabel` and `.accessibilityValue` containing the chart's semantic
summary (e.g., "Distance by sport chart: Rower 45 km, SkiErg 12 km").

This preserves the data for VoiceOver users while giving Computer Use a clean
text representation instead of the framework's internal chart AX tree.

Affected views:
- `DashboardView` — Distance by Sport chart, Recent Pace chart
- `WorkoutDetailView` — Stroke Timeline chart

### If RealityKit is the offender

`RealityReplaySceneView` already has `.accessibilityElement(children: .ignore)`
with label "3D workout replay" and value containing sport/progress/pace. This
should be sufficient. If the RealityView itself generates incompatible children
despite `.ignore`, the fix is to ensure the entire RealityView subtree is
excluded from accessibility.

### If Canvas is the offender

`ReplayView.replayCanvas` already has `.accessibilityLabel("Workout replay
timeline")`. The Canvas itself should not generate child accessibility elements.
If it does, wrap with `.accessibilityElement(children: .ignore)`.

## Bundle Metadata Hardening

### Current State

The `build_and_run.sh` script generates Info.plist but does not:
1. Set `CFBundleName` to match the executable name (`RowPlayStudio`)
2. Ad-hoc sign the bundle
3. Verify the bundle with `codesign`

### Target State

Update Info.plist generation to use `CFBundleName = RowPlayStudio` (technical
identity) while keeping `CFBundleDisplayName = RowPlay Studio` (human-facing).
Add ad-hoc signing after bundle assembly:

```bash
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
```

This ensures:
- Computer Use can discover the app by bundle identifier
- The bundle passes macOS validation
- No external signing certificates are required

### Bundle Identity Table

| Field | Value | Purpose |
|---|---|---|
| CFBundleExecutable | RowPlayStudio | binary name |
| CFBundleIdentifier | com.shenghaoc.RowPlayStudio | unique ID |
| CFBundleName | RowPlayStudio | technical name |
| CFBundleDisplayName | RowPlay Studio | human-facing name |
| LSMinimumSystemVersion | 26.0 | macOS 26+ |

## Automation Launch Mode

`./script/build_and_run.sh --automation` will:

1. Build and stage the app (same as `run`)
2. Set `ROWPLAY_AUTOMATION=1` environment variable via `open --env`
3. The app reads this at launch and:
   - Forces demo mode (deterministic data)
   - Disables Concept2 sync background task
   - Sets isolation to `full` (production surface must work)
   - Disables nonessential animation (reduce motion)

The `--automation` flag is passed through `open --env` which requires no code
changes to the app beyond reading the environment variable.

## Distinguishing Concepts

| Concept | Owner | Computer Use Impact |
|---|---|---|
| App accessibility semantics | RowPlayStudio views | What the helper reads |
| Computer Use host permissions | macOS TCC | Whether helper can access app |
| ScreenCaptureKit indicator | System | Screenshot capability, not audio |
| Helper screenshot phase | SkyComputerUseService | Visual capture before AX tree |
| Helper AX tree phase | SkyComputerUseService | Semantic traversal (crash point) |

The crash is in the AX tree phase, not the screenshot phase. The
ScreenCaptureKit indicator is unrelated to the crash.

## File Changes Expected

| File | Change |
|---|---|
| `Sources/RowPlayStudio/App/IsolationConfig.swift` | NEW — isolation config |
| `Sources/RowPlayStudio/App/RowPlayStudioApp.swift` | Read isolation env, pass config |
| `Sources/RowPlayStudio/Views/DashboardView.swift` | Wrap charts with accessibility summary |
| `Sources/RowPlayStudio/Views/WorkoutDetailView.swift` | Wrap chart with accessibility summary |
| `Sources/RowPlayStudio/Views/ReplayView.swift` | Check canvas accessibility |
| `script/build_and_run.sh` | Add `--automation`, signing, verify |
| `Tests/RowPlayStudioTests/ComputerUseAutomationReadinessTests.swift` | NEW — focused tests |
| `.kiro/specs/computer-use-automation-readiness/*` | This spec |
| `docs/roadmap.md` | Add phase status |
| `docs/beta-readiness.md` | Update verified section |
| `docs/source-map.md` | Add new file entries |
