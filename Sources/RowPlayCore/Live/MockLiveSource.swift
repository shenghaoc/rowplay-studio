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
        let sport = sportDistribution[rng.next(in: 0...(sportDistribution.count - 1))]
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
        case .rower:   strokeRate = Double(rng.next(in: 18...32))
        case .skierg:  strokeRate = Double(rng.next(in: 24...40))
        case .bike:    strokeRate = Double(rng.next(in: 60...100))
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
            heartRateAvg: rng.next(in: 120...175),
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
            let distance = Double(rng.next(in: 2_000...10_000))
            let pacePer500m = TimeInterval(rng.next(in: 110...145))
            let time = distance / 500.0 * pacePer500m
            return (distance, time, pacePer500m)
        case .skierg:
            let distance = Double(rng.next(in: 1_000...5_000))
            let pacePer500m = TimeInterval(rng.next(in: 105...140))
            let time = distance / 500.0 * pacePer500m
            return (distance, time, pacePer500m)
        case .bike:
            let distance = Double(rng.next(in: 4_000...20_000))
            let pacePer500m = TimeInterval(rng.next(in: 75...110))
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

    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.count)
        let offset = next() % span
        return range.lowerBound + Int(offset)
    }
}
