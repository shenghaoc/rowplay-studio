import Foundation

/// Personal best detection at standard Concept2 distances.
///
/// Ported from `analytics.ts` (`distancePBs`) and `workoutQuery.ts` (`pbWorkoutIds`).
public struct PersonalBest: Equatable, Sendable {
    public let distance: Double
    public let sport: Sport
    public let time: TimeInterval
    public let date: Date

    public init(distance: Double, sport: Sport, time: TimeInterval, date: Date) {
        self.distance = distance
        self.sport = sport
        self.time = time
        self.date = date
    }
}

public enum PersonalBests {
    /// Standard Concept2 race distances for PB tracking.
    public static let standardDistances: [Double] = [500, 1000, 2000, 5000, 6000, 10000, 21_097, 42_195]

    /// Distance matching tolerance (±2%).
    private static let distanceTolerance = 0.02

    /// Returns the fastest workout per standard distance across all workouts.
    /// When `sport` is non-nil, only workouts matching that sport are considered.
    public static func distancePBs(for workouts: [Workout], sport: Sport? = nil) -> [PersonalBest] {
        bestWorkoutsPerStandardDistance(for: workouts, sport: sport).map { best in
            PersonalBest(
                distance: best.distance,
                sport: best.workout.sport,
                time: best.workout.time,
                date: best.workout.date
            )
        }
    }

    /// Returns the set of workout IDs that are PBs at any standard distance.
    /// When `sport` is non-nil, only workouts matching that sport are considered.
    public static func pbWorkoutIds(for workouts: [Workout], sport: Sport? = nil) -> Set<Int> {
        Set(bestWorkoutsPerStandardDistance(for: workouts, sport: sport).map { $0.workout.id })
    }

    /// Returns the canonical standard distance matched by a workout distance.
    public static func standardDistance(matching distance: Double) -> Double? {
        standardDistances.first { target in
            abs(distance - target) <= target * distanceTolerance
        }
    }

    private static func bestWorkoutsPerStandardDistance(
        for workouts: [Workout],
        sport: Sport?
    ) -> [(distance: Double, workout: Workout)] {
        let filtered = sport.map { s in workouts.filter { $0.sport == s } } ?? workouts
        var bests: [(distance: Double, workout: Workout)] = []

        for target in standardDistances {
            guard let best = bestWorkout(in: filtered, for: target) else { continue }
            bests.append((distance: target, workout: best))
        }

        return bests
    }

    private static func bestWorkout(in workouts: [Workout], for target: Double) -> Workout? {
        workouts
            .filter { workout in
                abs(workout.distance - target) <= target * distanceTolerance && workout.time > 0
            }
            .min { a, b in a.time < b.time }
    }
}
