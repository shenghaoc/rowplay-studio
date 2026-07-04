import Foundation

/// Injectable protocol for ergometer hardware connections.
///
/// This defines the boundary for future Bluetooth, USB, or other hardware
/// transports. It does NOT import CoreBluetooth, AppKit, or SwiftUI.
/// Implementations should be usable from unit tests without real hardware.
public protocol ErgConnection: Sendable {
    /// Current connection state.
    var currentState: ErgConnectionState { get async }

    /// Connect to the specified device.
    func connect(to device: ErgDevice) async throws

    /// Disconnect from the current device.
    func disconnect() async

    /// Returns an async stream of telemetry samples from the connected device.
    ///
    /// The stream should yield samples at a regular interval while connected.
    /// It should finish when the connection is closed or lost.
    func telemetryStream() -> AsyncStream<ErgTelemetrySample>
}
