# Tasks: Wire Native Settings

- [x] 1. Add `DistanceUnit` enum and `distance(_:unit:)` to `RowPlayFormatting`
- [x] 2. Add tests for metric and imperial distance formatting
- [x] 3. Create `Sources/RowPlayStudio/Stores/AppPreferences.swift`
- [x] 4. Update `WorkoutLibrary` with `isEmpty` and `clearData()`
- [x] 5. Update `RowPlayStudioApp` to create and inject `AppPreferences`
- [x] 6. Update `SettingsView` to use `@EnvironmentObject`
- [x] 7. Wire `preferredDistanceUnit` through `ContentView`, `SidebarView`, `DashboardView`
- [x] 8. Wire `preferredDistanceUnit` through `WorkoutDetailView`, `ReplayView`, `LiveModePanelView`
- [x] 9. Wire `reduceReplayMotion` in `ReplayView`
- [x] 10. Wire `demoModeEnabled` in `ContentView` and `RowPlayStudioApp`
- [x] 11. Add app-target tests for shared preferences and demo library clear/reload behavior
- [x] 12. Update `docs/beta-readiness.md` and `docs/source-map.md`
- [x] 13. Validate: `swift test`, `swift build`, `git diff --check`
