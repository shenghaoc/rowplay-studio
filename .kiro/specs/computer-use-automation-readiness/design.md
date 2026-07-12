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

## Confirmed Diagnosis

`SkyComputerUseService` terminated with `EXC_BREAKPOINT` / `SIGTRAP` while it
held AX observers for RowPlayStudio. Progressive isolation established that the
minimal window, sidebar, chart-free detail, and `WorkoutToolsView` heading all
traverse successfully. The generated SwiftUI accessibility representation of a
`GroupBox("Annotations")` still crashes the helper when its content is reduced
to one static `Text`; that is the confirmed offending representation.

The exact source-level AX boundary is therefore the framework-generated
`GroupBox` container labelled `Annotations`, not its text field, slider,
annotation list, Charts, Canvas, or RealityKit content. The helper crashes
before it serializes a stable AX role for that `GroupBox`, so the production
fix removes the representation rather than hiding its content.

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

1. `minimal` and `sidebar_only` returned semantic trees.
2. `no_charts` still crashed, excluding Charts as the primary cause.
3. The temporary chart-free tools isolation succeeded; a static
   `GroupBox("Annotations")` reproduced the crash.
4. Replace all workout-tool `GroupBox` containers, then retest `full`.
5. `full` returned the complete app tree and both 2D and 3D replay surfaces.

Launch a level reproducibly with:

```bash
./script/build_and_run.sh --verify --isolation no_charts
```

The script passes the level directly to the staged bundle with `open --env`;
setting an environment variable in the invoking shell alone is not reliable
for a Launch Services launch.

### Safety

- `IsolationConfig` lives in `RowPlayStudio` only (not Core or Platform)
- Defaults to `.full` — zero behavior change for normal launches
- The `--automation` flag uses the full production surface with demo mode
- Temporary probes are removed after diagnosis; only the final config remains

## Remediation

`WorkoutToolSection` replaces `GroupBox` in the export/share, HR import,
comparison, and annotations panels. It uses an explicit heading, visual
container, `.accessibilityElement(children: .contain)`, and an explicit label.
This preserves every child control and its action for VoiceOver and Computer
Use. The verified tree exposes each section as a container, its heading, and
all buttons, picker, slider, text field, and annotation actions.

The existing chart summaries and replay labels remain semantically correct and
also traverse successfully on the full surface.

## Bundle Metadata Hardening

The staged bundle now uses `CFBundleName = RowPlayStudio` (technical identity)
and `CFBundleDisplayName = RowPlay Studio` (human-facing). It is ad-hoc signed
and strictly verified after bundle assembly:

```bash
codesign --force --deep --sign - --identifier com.shenghaoc.RowPlayStudio "$APP_BUNDLE"
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

### Diagnostics

The `automation-readiness` OSLog category emits only the bundle identifier,
technical bundle name, automation flag, isolation level, and confirmation that
the main content was presented. It contains no workout, account, or filesystem
data. This distinguishes a successful app launch and visible shell from a
Computer Use failure. The Computer Use result and the newest
`SkyComputerUseService` crash report remain the evidence for helper-side AX
traversal or helper crashes; the app cannot truthfully claim to observe those
host-process failures.

## File Changes Expected

| File | Change |
|---|---|
| `Sources/RowPlayStudio/App/IsolationConfig.swift` | NEW — isolation config |
| `Sources/RowPlayStudio/App/RowPlayStudioApp.swift` | Read isolation env, pass config |
| `Sources/RowPlayStudio/Views/DashboardView.swift` | Wrap charts with accessibility summary |
| `Sources/RowPlayStudio/Views/WorkoutDetailView.swift` | Wrap chart with accessibility summary |
| `Sources/RowPlayStudio/Views/ReplayView.swift` | Check canvas accessibility |
| `Sources/RowPlayStudio/Views/WorkoutToolSection.swift` | Explicit semantic replacement for incompatible workout-tool `GroupBox` containers |
| `script/build_and_run.sh` | Add `--automation`, signing, verify |
| `Tests/RowPlayStudioTests/ComputerUseAutomationReadinessTests.swift` | NEW — focused tests |
| `.kiro/specs/computer-use-automation-readiness/*` | This spec |
| `docs/roadmap.md` | Add phase status |
| `docs/beta-readiness.md` | Update verified section |
| `docs/source-map.md` | Add new file entries |
