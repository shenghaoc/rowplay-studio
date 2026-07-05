# Design: Wire Native Settings

## Architecture

### AppPreferences Store

Create `Sources/RowPlayStudio/Stores/AppPreferences.swift` as the single published settings model:

```swift
@MainActor
final class AppPreferences: ObservableObject {
    @Published var demoModeEnabled: Bool
    @Published var reduceReplayMotion: Bool
    @Published var preferredDistanceUnit: String
}
```

The model reads and writes the existing `UserDefaults` keys:

- `demoModeEnabled`
- `reduceReplayMotion`
- `preferredDistanceUnit`

Injected via `@EnvironmentObject` from `RowPlayStudioApp`. All views read from this single instance so settings changes publish through `objectWillChange`.

### Distance Formatting

Add `DistanceUnit` enum to `Sources/RowPlayCore/Models/DistanceUnit.swift`:

- `DistanceUnit` enum: `.metric`, `.imperial`
- `distance(_:unit:)` static method on `RowPlayFormatting`

Metric behavior: unchanged from current `distance(_:)`.

Imperial behaviour:
- Metres < 304.8 (1000 feet): show feet, e.g. `"500 ft"`
- Metres >= 304.8: show miles, e.g. `"0.31 mi"`, `"3.11 mi"`
- Non-finite values: `"--"`

Pace remains `/500m` always (no change).

### Wiring Plan

| File | Change |
|---|---|
| `RowPlayStudioApp.swift` | Create `@StateObject` preferences, inject via `.environmentObject`, wire demo mode toggle |
| `SettingsView.swift` | Replace local settings storage with `@EnvironmentObject` |
| `ContentView.swift` | Add `@EnvironmentObject`, empty state when demo off |
| `SidebarView.swift` | Read distance unit from environment, format with `distance(_:unit:)` |
| `DashboardView.swift` | Read distance unit from environment, format with `distance(_:unit:)` |
| `WorkoutDetailView.swift` | Read distance unit from environment, format with `distance(_:unit:)` |
| `ReplayView.swift` | Read `reduceReplayMotion` and distance unit from environment |
| `LiveModePanelView.swift` | Read distance unit from environment |
| `WorkoutLibrary.swift` | Add `isEmpty`, `clearData()` helpers |

### Reduce Motion

In `ReplayView`, when `reduceReplayMotion` is `true`:
- Timeline animation interval drops from 60fps to 15fps
- Playback controls still work

### Demo Mode

- `RowPlayStudioApp` owns the `AppPreferences` `@StateObject`
- When `demoModeEnabled` changes to `false`, `WorkoutLibrary.clearData()` is called
- When it changes to `true` and library is empty, `reloadDemoData()` is called
- `ContentView` shows `ContentUnavailableView` when library is empty and demo mode is off
- The "Reload Demo Library" button/command is disabled when demo mode is off

## Non-Goals

- No new persisted setting keys
- No new settings controls
- No Concept2 sync, SQLite, or CoreBluetooth
- No replay renderer rewrite
