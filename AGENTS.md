# Repository Guidelines

## Project Structure & Module Organization

RowPlay Studio is a SwiftPM macOS app with two main targets. Keep reusable domain logic in `Sources/RowPlayCore/` and app-only SwiftUI code in `Sources/RowPlayStudio/`. Core subfolders include `Models/`, `Analytics/`, `Replay/`, `Sync/`, `Live/`, `Connectivity/`, `Compare/`, `Import/`, `Export/`, `Share/`, and `Support/`. App code is split across `App/`, `Stores/`, and `Views/`. Tests live in `Tests/RowPlayCoreTests/`, with JSON parity fixtures under `Tests/RowPlayCoreTests/Fixtures/`. Roadmap and web parity references are in `docs/` and phase specs are in `.kiro/specs/`.

## Build, Test, and Development Commands

- `swift test`: runs the XCTest suite.
- `swift test --filter WorkoutAnalyticsTests`: runs a focused test class or method.
- `swift build`: builds the package and mirrors CI's build step.
- `./script/build_and_run.sh`: builds, stages `dist/RowPlayStudio.app`, and launches it.
- `./script/build_and_run.sh --verify`: launches the staged app and verifies the process is running.
- `./script/build_and_run.sh --logs` or `--telemetry`: launches with live unified logging.

Do not launch the raw SwiftPM executable for GUI verification; use the script so the app bundle layout is realistic.

## Coding Style & Naming Conventions

Use standard Swift formatting with 4-space indentation and descriptive type names. Test files use `ThingTests.swift`; test methods use `testBehaviorUnderCondition()`. Keep SwiftUI, AppKit, and process behavior out of `RowPlayCore`; define external boundaries as protocols and inject mocks for tests. Prefer deterministic demo data and avoid render-time O(N) derived work in SwiftUI views; cache expensive library summaries in stores.

## Testing Guidelines

Use XCTest for core behavior. Add tests for every new pure helper, storage/sync boundary, parser, replay rule, or parity port. When porting web behavior, add or update fixtures in `Tests/RowPlayCoreTests/Fixtures/` and verify native output against known values. Run `swift test`, `swift build`, and `git diff --check` before opening a PR; add `./script/build_and_run.sh --verify` for UI launch or bundle changes.

## Commit & Pull Request Guidelines

Recent history uses concise subject lines such as `feat: Phase 6 - Live Mode Foundation (#9)` or `Phase 7: Hardware connectivity foundation (#10)`. Keep commits scoped to one phase or fix. PRs should explain scope, list validation commands, link the relevant phase spec or issue, and include screenshots or notes for visible UI changes. Call out exclusions and known gaps explicitly.

## Security & Configuration Tips

Concept2 tokens must stay in Keychain-backed storage, never `UserDefaults`, plain files, logs, or fixtures. Use `PrivacySafeLogger` and redaction helpers for user data. Preserve demo mode as fully explorable without credentials.
