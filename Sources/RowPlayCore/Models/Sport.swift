import Foundation

public enum Sport: String, CaseIterable, Codable, Identifiable, Sendable {
    case rower
    case skierg
    case bike

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rower:
            "RowErg"
        case .skierg:
            "SkiErg"
        case .bike:
            "BikeErg"
        }
    }

    public var shortName: String {
        switch self {
        case .rower:
            "Row"
        case .skierg:
            "Ski"
        case .bike:
            "Bike"
        }
    }

    public var iconName: String {
        switch self {
        case .rower:
            "figure.rower"
        case .skierg:
            "figure.skiing.crosscountry"
        case .bike:
            "bicycle"
        }
    }

    public var cadenceUnit: String {
        switch self {
        case .bike:
            "rpm"
        case .rower, .skierg:
            "spm"
        }
    }

    public static func fromConcept2Type(_ type: String?) -> Sport {
        switch type?.lowercased() {
        case "ski", "skierg":
            .skierg
        case "bike", "bikeerg":
            .bike
        default:
            .rower
        }
    }
}

