# Phase 7 Requirements: Hardware Connectivity Foundation

## R1: Ergometer Device Model

The native app must define a value type representing a discovered ergometer device.

- **R1.1** `ErgDevice` struct has a stable `id` (UUID), `displayName` (String), and optional `manufacturer` (String).
- **R1.2** `ErgDevice` includes a `sport` property (optional `Sport`) to indicate the machine type when known.
- **R1.3** `ErgDevice` includes a `connectionKind` enum: `mock`, `bluetooth`, `usb`, `unknown`.
- **R1.4** `ErgDevice` conforms to `Equatable`, `Identifiable`, `Sendable`, and `Codable`.

## R2: Connection State Machine

The native app must define an enum for hardware connection lifecycle states.

- **R2.1** `ErgConnectionState` enum defines states: `disconnected`, `scanning`, `connecting`, `connected`, `failed`.
- **R2.2** `ErgConnectionState` conforms to `Equatable`, `Sendable`, and `Hashable`.
- **R2.3** The `failed` case carries a human-readable `reason` string.

## R3: Telemetry Sample Model

The native app must define a value type for live hardware telemetry samples.

- **R3.1** `ErgTelemetrySample` struct includes: `elapsed` (TimeInterval), `distance` (Double), `pace` (TimeInterval), `cadence` (Double), `watts` (Int), optional `heartRate` (Int), and `timestamp` (Date).
- **R3.2** `ErgTelemetrySample` conforms to `Equatable`, `Sendable`, and `Codable`.
- **R3.3** Field names and units are compatible with existing `Stroke` and `LiveWorkoutSample` models where applicable.

## R4: Connection Protocol Boundary

The native app must define an injectable protocol for hardware connections.

- **R4.1** `ErgConnection` protocol defines the boundary for future hardware transports.
- **R4.2** The protocol does NOT import CoreBluetooth, AppKit, or SwiftUI.
- **R4.3** The protocol is usable from unit tests without real hardware.
- **R4.4** The protocol supports connecting, disconnecting, and receiving telemetry updates.

## R5: Mock Connection Implementation

The native app must provide a deterministic mock hardware connection for testing and UI development.

- **R5.1** `MockErgConnection` simulates connection state changes without real hardware.
- **R5.2** `MockErgConnection` emits deterministic telemetry samples.
- **R5.3** `MockErgConnection` does not require network or Bluetooth.
- **R5.4** `MockErgConnection` is usable in unit tests with manual tick advancement.
- **R5.5** In-flight mock connection attempts must not overwrite a later disconnect or failure state.
- **R5.6** Resetting a mock connection must preserve the instance's original deterministic seed.
- **R5.7** Replacing or terminating telemetry streams must clean up stale continuations.
- **R5.8** Mock telemetry pace must remain positive so distance never moves backward, even with unusual base pace inputs.

## R6: Module Boundaries

- **R6.1** All hardware connectivity domain logic lives in `RowPlayCore/Connectivity/`.
- **R6.2** No CoreBluetooth imports in `RowPlayCore` in this PR.
- **R6.3** No SwiftUI or AppKit imports in `RowPlayCore` in this PR.
- **R6.4** No entitlements, Info.plist Bluetooth permission strings, or background hardware sessions.

## R7: Test Coverage

- **R7.1** `MockErgConnectionTests` cover connection state transitions.
- **R7.2** `MockErgConnectionTests` cover deterministic telemetry output.
- **R7.3** `ErgTelemetrySampleTests` cover sample field validation.
- **R7.4** Tests verify mock connection starts disconnected.
- **R7.5** Tests verify mock connection can transition to connected.
- **R7.6** Tests verify mock connection can transition back to disconnected.
- **R7.7** Tests verify mock telemetry elapsed time increases.
- **R7.8** Tests verify mock telemetry distance does not go backward.
- **R7.9** Tests verify mock telemetry contains cadence and watts.
- **R7.10** Tests verify failure state preserves a human-readable reason.
- **R7.11** Tests verify in-flight connect cancellation/failure does not resurrect the connection.
- **R7.12** Tests verify custom-seed reset restores the original deterministic sequence.
- **R7.13** Tests verify replacing the telemetry stream finishes the previous stream.
- **R7.14** Tests verify non-positive base pace is clamped to a positive value.
- **R7.15** `swift test` passes.
- **R7.16** `swift build` passes.

## R8: Non-Goals

- No real Bluetooth scanning or device discovery.
- No real device pairing.
- No CoreBluetooth entitlement or permission work.
- No real FTMS protocol implementation.
- No real Concept2 PM protocol implementation.
- No replay renderer changes.
- No export/share/annotation code changes.
- No Concept2 sync changes.
- No menu bar or background behavior.
