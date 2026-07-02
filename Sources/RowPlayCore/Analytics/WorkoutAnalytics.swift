import Foundation

public struct SportSummary: Equatable, Identifiable, Sendable {
    public var sport: Sport
    public var sessions: Int
    public var distance: Double
    public var time: TimeInterval
    public var averagePace: TimeInterval
    public var bestPace: TimeInterval
    public var longestDistance: Double

    public var id: Sport { sport }
}

public struct DashboardSummary: Equatable, Sendable {
    public var sessions: Int
    public var totalDistance: Double
    public var challengeDistance: Double
    public var totalTime: TimeInterval
    public var averagePace: TimeInterval
    public var bySport: [SportSummary]
}

public struct DashboardPersonalBest: Equatable, Identifiable, Sendable {
    public var id: Int
    public var distance: Double
    public var time: TimeInterval
    public var date: Date
}

public struct DistanceBand: Equatable, Sendable {
    public var key: String
    public var label: String
    public var nominalMetres: Double
}

public struct TrendFit: Equatable, Sendable {
    public var slopePerDay: Double
    public var y0: Double
    public var y1: Double
    public var delta: Double
    public var count: Int
}

public enum WorkoutAnalytics {
    public static func dashboardSummary(for workouts: [Workout]) -> DashboardSummary {
        let totalDistance = workouts.reduce(0) { $0 + $1.distance }
        let challengeDistance = workouts.reduce(0) { $0 + RowPlayFormatting.challengeDistance(for: $1) }
        let totalTime = workouts.reduce(0) { $0 + $1.time }
        let averagePace = totalDistance > 0 ? totalTime / (totalDistance / 500) : 0

        return DashboardSummary(
            sessions: workouts.count,
            totalDistance: totalDistance,
            challengeDistance: challengeDistance,
            totalTime: totalTime,
            averagePace: averagePace,
            bySport: summariseBySport(workouts)
        )
    }

    public static func summariseBySport(_ workouts: [Workout]) -> [SportSummary] {
        let grouped = Dictionary(grouping: workouts, by: \.sport)

        return grouped.map { sport, sportWorkouts in
            let distance = sportWorkouts.reduce(0) { $0 + $1.distance }
            let time = sportWorkouts.reduce(0) { $0 + $1.time }
            let averagePace = distance > 0 ? time / (distance / 500) : 0
            let bestPace = sportWorkouts.map(\.pace).min() ?? 0
            let longest = sportWorkouts.map(\.distance).max() ?? 0

            return SportSummary(
                sport: sport,
                sessions: sportWorkouts.count,
                distance: distance,
                time: time,
                averagePace: averagePace,
                bestPace: bestPace,
                longestDistance: longest
            )
        }
        .sorted { lhs, rhs in
            if lhs.distance == rhs.distance {
                return lhs.sport.rawValue < rhs.sport.rawValue
            }
            return lhs.distance > rhs.distance
        }
    }

    public static func dashboardPersonalBests(for workouts: [Workout], pbIds: Set<Int>) -> [DashboardPersonalBest] {
        workouts
            .compactMap { workout -> DashboardPersonalBest? in
                guard pbIds.contains(workout.id),
                      let standardDistance = PersonalBests.standardDistance(matching: workout.distance)
                else {
                    return nil
                }

                return DashboardPersonalBest(
                    id: workout.id,
                    distance: standardDistance,
                    time: workout.time,
                    date: workout.date
                )
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.date > rhs.date
                }
                return lhs.distance < rhs.distance
            }
    }

    public static func recentPaceWorkouts(
        for workouts: [Workout],
        sport: Sport,
        limit: Int
    ) -> [Workout] {
        guard limit > 0 else {
            return []
        }

        return Array(
            workouts
                .filter { $0.sport == sport }
                .sorted { $0.date < $1.date }
                .suffix(limit)
        )
    }

    public static func distanceBand(for metres: Double) -> DistanceBand {
        let standards: [(Double, String)] = [
            (100, "100m"),
            (500, "500m"),
            (1_000, "1k"),
            (2_000, "2k"),
            (5_000, "5k"),
            (6_000, "6k"),
            (10_000, "10k"),
            (21_097, "Half"),
            (42_195, "Full")
        ]

        for standard in standards where abs(metres - standard.0) <= standard.0 * 0.06 {
            return DistanceBand(key: "\(Int(standard.0))", label: standard.1, nominalMetres: standard.0)
        }

        let ranges: [(Double, Double, String)] = [
            (0, 750, "<750m"),
            (750, 1_500, "750m-1.5k"),
            (1_500, 3_000, "1.5k-3k"),
            (3_000, 7_000, "3k-7k"),
            (7_000, 15_000, "7k-15k"),
            (15_000, .infinity, "15k+")
        ]

        for range in ranges where metres >= range.0 && metres < range.1 {
            let upper = range.0 == 0 ? range.1 : min(range.1, range.0 * 2)
            return DistanceBand(key: "r\(Int(range.0))", label: range.2, nominalMetres: (range.0 + upper) / 2)
        }

        return DistanceBand(key: "other", label: "Other", nominalMetres: metres)
    }

    public static func linearTrend(points: [(x: Date, y: Double)]) -> TrendFit? {
        guard points.count >= 2 else {
            return nil
        }

        guard let firstDate = points.map(\.x).min() else {
            return nil
        }

        let dayPoints = points.map { point in
            ((point.x.timeIntervalSince(firstDate) / 86_400), point.y)
        }

        let count = Double(dayPoints.count)
        let sumX = dayPoints.reduce(0) { $0 + $1.0 }
        let sumY = dayPoints.reduce(0) { $0 + $1.1 }
        let meanX = sumX / count
        let meanY = sumY / count

        var numerator = 0.0
        var denominator = 0.0

        for point in dayPoints {
            numerator += (point.0 - meanX) * (point.1 - meanY)
            denominator += pow(point.0 - meanX, 2)
        }

        guard denominator != 0 else {
            return nil
        }

        let slope = numerator / denominator
        let intercept = meanY - slope * meanX
        let lastX = dayPoints.map(\.0).max() ?? 0
        let y0 = intercept
        let y1 = intercept + slope * lastX

        return TrendFit(
            slopePerDay: slope,
            y0: y0,
            y1: y1,
            delta: y1 - y0,
            count: points.count
        )
    }
}
