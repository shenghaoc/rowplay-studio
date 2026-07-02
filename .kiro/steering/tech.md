# Technical Steering

## Stack

- SwiftPM package-first macOS app.
- SwiftUI for the primary UI.
- `RowPlayCore` for reusable domain logic and future iOS portability.
- XCTest for core tests.
- Swift Charts for initial dashboard and workout telemetry charts.

## Validation

Use:

```bash
swift test
swift build
./script/build_and_run.sh --verify
```

The run script stages the SwiftPM GUI executable as a local `.app` bundle under `dist/` before launching it. Do not launch the raw SwiftPM executable for normal GUI verification.

## Future Storage And Sync

- Concept2 BYOT token storage should use Keychain.
- Workout cache should use a local database layer with explicit migration tests.
- Logs must redact tokens, cookies, and full raw workout payloads.
- Network clients should be injectable for tests.

