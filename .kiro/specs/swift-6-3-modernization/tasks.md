# Tasks: Swift 6.3 Modernization

## Implementation Tasks

- [x] Set `swift-tools-version` to 6.3 and explicitly select Swift language mode 6.
- [x] Add `.swift-version` pinned to 6.3.3.
- [x] Fix Swift 6.3 XCTest actor-isolation diagnostics.
- [x] Replace the HTTP transport's `nonisolated(unsafe)` task capture with checked synchronized state.
- [x] Set the package deployment target to macOS 26.
- [x] Adopt `Synchronization.Mutex` directly on macOS and Linux.
- [x] Convert mutable in-memory stores, mocks, redirect tracking, and formatter caches to checked synchronized state.
- [x] Replace shared `ISO8601DateFormatter` state with `Date.ISO8601FormatStyle`.
- [x] Add applicable `Sendable` conformances to namespace, error, and immutable client types.
- [x] Pin and assert Swift 6.3.3 in Linux and macOS CI.
- [x] Restore explicit SQLite development-header installation in Linux CI.
- [x] Treat Swift warnings as errors in every CI build and test command.
- [x] Run the full Swift 6.3.3 test suite with warnings as errors (726 tests, 2 opt-in authenticated tests skipped).
- [x] Run the full Swift 6.3.3 build with warnings as errors.
- [x] Stage and launch `dist/RowPlayStudio.app` with `--verify`.
- [x] Confirm the staged binary and Info.plist both require macOS 26.0.
- [x] Confirm the updated GitHub Actions jobs pass on the pushed head.
