import Foundation

/// Connection lifecycle state for an ergometer device.
///
/// Transitions:
/// ```
/// disconnected ──scan──▶ scanning
/// scanning ──found──▶ connecting
/// connecting ──success──▶ connected
/// connecting ──failure──▶ failed
/// connected ──disconnect──▶ disconnected
/// failed ──retry──▶ scanning
/// ```
public enum ErgConnectionState: Equatable, Hashable, Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case failed(reason: String)

    public var isConnected: Bool {
        self == .connected
    }

    public var isTerminal: Bool {
        switch self {
        case .disconnected, .failed:
            return true
        case .scanning, .connecting, .connected:
            return false
        }
    }
}
