# Phase 07 Hardware Connectivity Foundation Tasks

- [x] Create `Sources/RowPlayCore/Connectivity/ErgDevice.swift` with `ErgDevice` struct and `ErgConnectionKind` enum.
- [x] Create `Sources/RowPlayCore/Connectivity/ErgConnectionState.swift` with connection lifecycle enum including failed-reason.
- [x] Create `Sources/RowPlayCore/Connectivity/ErgTelemetrySample.swift` with telemetry sample value type.
- [x] Create `Sources/RowPlayCore/Connectivity/ErgConnection.swift` with injectable connection protocol.
- [x] Create `Sources/RowPlayCore/Connectivity/MockErgConnection.swift` with deterministic mock connection.
- [x] Create `Tests/RowPlayCoreTests/Connectivity/MockErgConnectionTests.swift` covering state transitions and deterministic telemetry.
- [x] Create `Tests/RowPlayCoreTests/Connectivity/ErgTelemetrySampleTests.swift` covering sample field validation.
- [x] Address review hardening for in-flight connect races, telemetry stream replacement, custom-seed reset, and non-positive pace inputs.
- [x] Create `.kiro/specs/phase-07-hardware-connectivity-foundation` spec documents.
- [x] Update `docs/source-map.md` with Phase 7 mappings.
- [x] Update `docs/roadmap.md` Phase 7 status.
- [x] Run `swift test` — all tests pass.
- [x] Run `swift build` — clean build.
- [x] Run `git diff --check` — no whitespace errors.
