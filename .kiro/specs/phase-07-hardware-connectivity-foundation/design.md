# Phase 7 Design: Hardware Connectivity Foundation

## Architecture

All new hardware connectivity domain logic lives in `RowPlayCore/Connectivity/`:

- `Sources/RowPlayCore/Connectivity/ErgDevice.swift` — value type for discovered ergometer devices
- `Sources/RowPlayCore/Connectivity/ErgConnectionState.swift` — connection lifecycle enum
- `Sources/RowPlayCore/Connectivity/ErgTelemetrySample.swift` — live hardware telemetry sample
- `Sources/RowPlayCore/Connectivity/ErgConnection.swift` — injectable protocol boundary
- `Sources/RowPlayCore/Connectivity/MockErgConnection.swift` — deterministic mock for testing

## Device Model

`ErgDevice` is a value type representing a discovered ergometer. It carries enough metadata for a future device picker UI but does not attempt to model Bluetooth-specific details (RSSI, service UUIDs, etc.) which belong in a real transport layer.

Fields:
- `id: UUID` — stable identifier assigned at discovery time
- `displayName: String` — human-readable device name
- `manufacturer: String?` — optional manufacturer string
- `sport: Sport?` — machine type when known (reuses existing `Sport` enum)
- `connectionKind: ErgConnectionKind` — transport type enum

`ErgConnectionKind` enum: `mock`, `bluetooth`, `usb`, `unknown`.

## Connection State

`ErgConnectionState` models the connection lifecycle:

```
disconnected ──scan──▶ scanning
scanning ──found──▶ connecting
connecting ──success──▶ connected
connecting ──failure──▶ failed
connected ──disconnect──▶ disconnected
failed ──retry──▶ scanning
```

The `failed` case carries a `reason: String` for human-readable diagnostics.

## Telemetry Sample

`ErgTelemetrySample` represents one point-in-time hardware reading. Field names and units align with existing models:

- `elapsed: TimeInterval` — seconds since workout start (matches `Stroke.t`, `LiveWorkoutSample.time`)
- `distance: Double` — meters (matches `Stroke.d`, `LiveWorkoutSample.distance`)
- `pace: TimeInterval` — seconds per 500m (matches `Stroke.pace`, `LiveWorkoutSample.pace`)
- `cadence: Double` — strokes/min or rpm (matches `Stroke.cadence`)
- `watts: Int` — instantaneous power (matches `Stroke.watts`)
- `heartRate: Int?` — optional BPM (matches `Stroke.heartRate`)
- `timestamp: Date` — wall-clock time of the sample

## Connection Protocol

`ErgConnection` defines the boundary for future hardware transports:

```swift
public protocol ErgConnection: Sendable {
    var currentState: ErgConnectionState { get async }
    func connect(to device: ErgDevice) async throws
    func disconnect() async
    func telemetryStream() -> AsyncStream<ErgTelemetrySample>
}
```

This protocol:
- Does NOT import CoreBluetooth
- Does NOT import AppKit or SwiftUI
- Is testable with a mock implementation
- Uses `AsyncStream` for telemetry delivery, matching Swift concurrency patterns

## Mock Connection

`MockErgConnection` provides deterministic behavior for testing:

- Starts in `disconnected` state
- `connect(to:)` transitions through `connecting` → `connected`
- `disconnect()` transitions to `disconnected`
- `simulateFailure(reason:)` transitions to `failed` with a reason
- `emitSample()` pushes a deterministic telemetry sample to the stream
- Telemetry is generated from a seeded PRNG (reusing `SeededGenerator` pattern from Phase 6)

The mock does NOT use real timers. Tests call `emitSample()` directly for deterministic advancement.

Review hardening added to the mock:
- Connection attempts use an attempt token so a delayed `connect(to:)` cannot overwrite a later `disconnect()` or `simulateFailure(reason:)`.
- Cancelled connection attempts clean up `connecting` state and clear the connected device reference when no later state transition superseded them.
- Reset restores the initial seed supplied to the instance, keeping custom-seed sequences deterministic.
- `telemetryStream()` finishes any previous stream before replacing it and clears the stored continuation when the active stream terminates.
- `simulateFailure(reason:)` finishes the active telemetry stream and clears the connected device reference.
- Generated pace is clamped to a positive minimum before deriving distance, preventing infinite or negative distance increments for unusual mock inputs.
- Generated cadence, watts, and heart rate values are clamped to non-negative values for unusual mock inputs.
- Mock sample timestamps are derived from elapsed time so full sample equality remains deterministic for a given seed and tick sequence.

## Mock-Only Settings Hook

The Settings view includes a small Hardware section that reports `Erg connection` as `Mock only` and states that Bluetooth devices are not available in this build. This is intentionally informational: it does not expose pairing controls, permission prompts, device scans, or background hardware behavior.

This keeps the user experience honest while the underlying Phase 7 boundary exists without a real transport.

## Relationship to Phase 6 Live Sources

Phase 6 established `LiveSource` for poll-based workout data from Concept2's API. Phase 7 adds a lower-level boundary for direct hardware connections. These are complementary:

- `LiveSource` — polls an API for completed workout data
- `ErgConnection` — streams real-time telemetry from a connected device

Future work can bridge `ErgConnection` telemetry into the existing `LiveWorkoutSample` / replay model. This PR does NOT wire them together.

## Naming Conventions

- `Erg` prefix distinguishes hardware-specific types from API-based live types
- Swift `camelCase` for all properties
- Protocol-based design matches `LiveSource`, `TokenStore`, `Concept2Client` patterns
- Mock implementation follows `MockLiveSource`, `FakeTokenStore`, `MockConcept2Client` patterns
