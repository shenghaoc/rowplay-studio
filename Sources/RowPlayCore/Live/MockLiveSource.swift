import Foundation

/// Demo live source that generates realistic mock workouts for QA and UI development.
///
/// Tracks generated IDs internally and increments them to avoid collisions.
/// Produces workouts with sport-appropriate distance ranges and realistic pacing.
public actor MockLiveSource: LiveSource {
    private var nextID: Int
    private let sportDistribution: [Sport]
    private var rng: SeededGenerator

    public init(startID: Int = 10_000, seed: UInt64 = 42) {
        self.nextID = startID
        self.rng = SeededGenerator(seed: seed)
        self.sportDistribution = [.rower, .rower, .rower, .skierg, .bike]
    }

    public func poll(knownIDs: Set<Int>) async throws -> LivePollResult {
        let sport = sportDistribution[Int.random(in: 0...(sportDistribution.count - 1), using: &rng)]
        let workout = generateWorkout(sport: sport)
        let workouts: [Workout] = knownIDs.contains(workout.id) ? [] : [workout]
        let added = workouts.count

        return LivePollResult(workouts: workouts, added: added, total: added)
    }

    private func generateWorkout(sport: Sport) -> Workout {
        let id = nextID
        nextID += 1

        let (distance, time, pace) = sportParameters(sport: sport)
        let strokeRate: Double
        switch sport {
        case .rower:   strokeRate = Double(Int.random(in: 18...32, using: &rng))
        case .skierg:  strokeRate = Double(Int.random(in: 24...40, using: &rng))
        case .bike:    strokeRate = Double(Int.random(in: 60...100, using: &rng))
        }

        return Workout(
            id: id,
            date: Date(),
            sport: sport,
            distance: distance,
            time: time,
            pace: pace,
            strokeRate: strokeRate,
            strokeCount: Int(time / (60.0 / strokeRate) * 1.0),
            heartRateAvg: Int.random(in: 120...175, using: &rng),
            caloriesTotal: Int(distance / 10.0),
            workoutType: "JustRow",
            source: "MockLive",
            verified: false,
            hasStrokeData: false,
            isInterval: false
        )
    }

    private func sportParameters(sport: Sport) -> (distance: Double, time: TimeInterval, pace: TimeInterval) {
        switch sport {
        case .rower:
            let distance = Double(Int.random(in: 2_000...10_000, using: &rng))
            let pacePer500m = TimeInterval(Int.random(in: 110...145, using: &rng))
            let time = distance / 500.0 * pacePer500m
            return (distance, time, pacePer500m)
        case .skierg:
            let distance = Double(Int.random(in: 1_000...5_000, using: &rng))
            let pacePer500m = TimeInterval(Int.random(in: 105...140, using: &rng))
            let time = distance / 500.0 * pacePer500m
            return (distance, time, pacePer500m)
        case .bike:
            let distance = Double(Int.random(in: 4_000...20_000, using: &rng))
            let pacePer500m = TimeInterval(Int.random(in: 75...110, using: &rng))
            let time = distance / 500.0 * pacePer500m
            return (distance, time, pacePer500m)
        }
    }
}

/// Simple seeded RNG for deterministic test output.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
