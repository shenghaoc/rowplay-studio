# Structure Steering

## Package Layout

```text
Sources/
  RowPlayCore/
    Models/       Domain values such as Sport, Workout, Stroke, Split.
    Analytics/    Pure calculations shared by app, tests, and future iOS.
    Fixtures/     Deterministic demo and parity fixtures.
    Support/      Formatting and small helpers.
  RowPlayStudio/
    App/          SwiftUI app entrypoint and app delegate.
    Stores/       Scene/app state stores.
    Views/        SwiftUI views split by surface.
    Support/      App-only glue.
Tests/
  RowPlayCoreTests/
```

## Rules

- Keep reusable math and data models in `RowPlayCore`.
- Keep SwiftUI, AppKit, and macOS process behavior out of `RowPlayCore`.
- Prefer native macOS affordances: split views, sidebars, settings scene, toolbar buttons, command menus, keyboard shortcuts.
- Add tests with each new pure helper or storage/sync behavior.
- Do not import Cloudflare assumptions into the native app. The web app itself no longer uses KV/D1 (removed in PR #166); native storage abstractions are native-local capabilities, not web parity.

