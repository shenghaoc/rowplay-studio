import Foundation

public enum DistanceUnit: String, CaseIterable, Sendable {
    case metric
    case imperial

    public static func from(_ raw: String) -> DistanceUnit {
        raw == "imperial" ? .imperial : .metric
    }
}
