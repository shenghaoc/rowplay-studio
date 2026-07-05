# Requirements: Wire Native Settings

## Context

PR #15 (audit) identified that `SettingsView` exposes three controls (`demoModeEnabled`, `reduceReplayMotion`, `preferredDistanceUnit`) that are not wired to any behavior. This PR connects them.

## Existing Settings

The following settings already exist in `SettingsView` with `@AppStorage` bindings:

| Key | Type | Default | Current state |
|---|---|---|---|
| `demoModeEnabled` | Bool | `true` | Not wired |
| `reduceReplayMotion` | Bool | `false` | Not wired |
| `preferredDistanceUnit` | String | `"metric"` | Not wired |

No new settings are added in this PR.

## Requirements

### R1: Shared Preferences Model

A single `AppPreferences` `ObservableObject` must expose all three persisted settings. All views that read these settings must use the shared model, not independent local `@AppStorage` instances.

### R2: Distance Unit Preference

- When `preferredDistanceUnit` is `"metric"`, distances display in metres/km.
- When `preferredDistanceUnit` is `"imperial"`, distances display in feet/miles.
- The setting must affect visible distance labels in: dashboard metric tiles, sidebar workout rows, workout detail metric strip, split table distance column, replay telemetry bar, and live mode sample metrics.
- Pace remains Concept2-style `/500m` regardless of distance unit.

### R3: Reduce Motion Preference

- When `reduceReplayMotion` is `true`, the replay view should disable decorative animation (e.g., the `TimelineView` animation loop).
- When `false`, animation runs normally.
- If the replay surface does not yet support meaningful reduced-motion behavior, the preference must still be exposed through app state with a clear note.

### R4: Demo Mode Preference

- When `demoModeEnabled` is `true`, the app loads demo workout data as it does today.
- When `demoModeEnabled` is `false` and no real synced workouts exist, the app shows an empty state (no workouts) instead of silently showing demo data.
- The "Reload Demo Library" command must respect this setting: when demo mode is off, the command either does nothing or is disabled.

### R5: No Duplicate Storage Keys

The `AppStorage` keys must remain `demoModeEnabled`, `reduceReplayMotion`, and `preferredDistanceUnit`. No duplicate keys with different names.

### R6: No New Features

This PR does not add Concept2 sync, SQLite persistence, CoreBluetooth, or any new settings.
