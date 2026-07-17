import Foundation

public enum RowPlayFormatting: Sendable {
    public static let bikeWattsFromNormalizedPaceDivisor = 8.0
    private static let feetThreshold: Double = 304.8 // 1000 feet in metres

    public static func time(_ seconds: TimeInterval, tenths: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }

        guard let hours = Int(exactly: (seconds / 3_600).rounded(.towardZero)) else {
            return "--:--"
        }
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        let remaining = seconds.truncatingRemainder(dividingBy: 60)

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", Int(remaining)))"
        }

        if tenths {
            return "\(minutes):\(String(format: "%04.1f", remaining))"
        }

        return "\(minutes):\(String(format: "%02d", Int(remaining)))"
    }

    public static func pace(_ secondsPer500m: TimeInterval) -> String {
        guard secondsPer500m.isFinite, secondsPer500m > 0 else {
            return "--:--"
        }
        return "\(time(secondsPer500m, tenths: true))/500m"
    }

    public static func distance(_ metres: Double, unit: DistanceUnit = .metric) -> String {
        guard metres.isFinite else {
            return "--"
        }
        switch unit {
        case .metric:
            if abs(metres) >= 1_000 {
                return "\(String(format: "%.2f", metres / 1_000)) km"
            }
            guard let roundedMetres = Int(exactly: metres.rounded()) else { return "--" }
            return "\(roundedMetres) m"
        case .imperial:
            if abs(metres) >= feetThreshold {
                let miles = metres / 1_609.344
                return "\(String(format: "%.2f", miles)) mi"
            }
            let feet = metres * 3.28084
            guard let roundedFeet = Int(exactly: feet.rounded()) else { return "--" }
            return "\(roundedFeet) ft"
        }
    }

    /// Distance formatting for race margins. Unlike general workout distance,
    /// positive sub-unit margins retain one decimal so a non-tie never renders
    /// as a misleading zero.
    public static func distanceMargin(
        _ metres: Double,
        unit: DistanceUnit = .metric
    ) -> String {
        guard metres.isFinite, metres >= 0 else { return "--" }
        switch unit {
        case .metric where metres > 0 && metres < 1:
            return "\(String(format: "%.1f", max(0.1, metres))) m"
        case .imperial:
            let feet = metres * 3.28084
            if metres > 0, feet < 1 {
                return "\(String(format: "%.1f", max(0.1, feet))) ft"
            }
            return distance(metres, unit: unit)
        case .metric:
            return distance(metres, unit: unit)
        }
    }

    public static func paceToWatts(_ pacePer500m: TimeInterval) -> Double {
        guard pacePer500m.isFinite, pacePer500m > 0 else {
            return 0
        }
        let perMetre = pacePer500m / 500
        return 2.8 / pow(perMetre, 3)
    }

    public static func paceToWatts(for sport: Sport, pacePer500m: TimeInterval) -> Double {
        let watts = paceToWatts(pacePer500m)
        return sport == .bike ? watts / bikeWattsFromNormalizedPaceDivisor : watts
    }

    public static func challengeDistance(for workout: Workout) -> Double {
        workout.sport == .bike ? workout.distance / 2 : workout.distance
    }
}
