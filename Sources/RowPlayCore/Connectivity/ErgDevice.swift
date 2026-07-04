import Foundation

/// Transport type for an ergometer connection.
public enum ErgConnectionKind: String, Codable, Sendable {
    case mock
    case bluetooth
    case usb
    case unknown
}

/// A discovered ergometer device.
///
/// Carries enough metadata for a future device picker UI without modeling
/// Bluetooth-specific details (RSSI, service UUIDs) which belong in a
/// real transport layer.
public struct ErgDevice: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let displayName: String
    public let manufacturer: String?
    public let sport: Sport?
    public let connectionKind: ErgConnectionKind

    public init(
        id: UUID = UUID(),
        displayName: String,
        manufacturer: String? = nil,
        sport: Sport? = nil,
        connectionKind: ErgConnectionKind = .unknown
    ) {
        self.id = id
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.sport = sport
        self.connectionKind = connectionKind
    }
}
