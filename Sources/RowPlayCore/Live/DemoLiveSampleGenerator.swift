import Foundation
import Synchronization

/// Snapshot of a workout in progress for live-mode UI display.
public struct LiveWorkoutSample: Equatable, Sendable, Identifiable {
    public let id: Int
    public let sport: Sport
    public let distance: Double
    public let time: TimeInterval
    public let pace: TimeInterval
    public let strokeRate: Double
    public let heartRateAvg: Int?
    public let date: Date

    public init(
        id: Int,
        sport: Sport,
        distance: Double,
        time: TimeInterval,
        pace: TimeInterval,
        strokeRate: Double,
        heartRateAvg: Int? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.sport = sport
        self.distance = distance
        self.time = time
        self.pace = pace
        self.strokeRate = strokeRate
        self.heartRateAvg = heartRateAvg
        self.date = date
    }
}

/// Generates sequential live workout samples that simulate a workout in progress.
///
/// Each call to `nextSample()` returns a sample with incrementally more distance
/// and time, with slight pace variation. Seeded for deterministic test output.
public final class DemoLiveSampleGenerator: Sendable {
    private struct State: Sendable {
        var elapsed: TimeInterval = 0
        var distance: Double = 0
        var rng: SeededGenerator
        var tick = 0
    }

    private let state: Mutex<State>
    private let id: Int
    private let sport: Sport
    private let basePace: TimeInterval
    private let baseStrokeRate: Double
    private let baseHR: Int
    private let initialSeed: UInt64

    public init(
        id: Int = 99_001,
        sport: Sport = .rower,
        basePace: TimeInterval = 125,
        baseStrokeRate: Double = 26,
        baseHR: Int = 155,
        seed: UInt64 = 123
    ) {
        self.id = id
        self.sport = sport
        self.basePace = basePace
        self.baseStrokeRate = baseStrokeRate
        self.baseHR = baseHR
        self.initialSeed = seed
        self.state = Mutex(State(rng: SeededGenerator(seed: seed)))
    }

    /// Returns the next sample in the sequence, advancing the workout by one segment.
    public func nextSample(at date: Date = Date()) -> LiveWorkoutSample {
        state.withLock { state in
            state.tick += 1

            // Advance by 30 seconds per tick, matching a typical poll interval chunk
            let segmentDuration: TimeInterval = 30
            state.elapsed += segmentDuration

            // Pace varies ±5 sec/500m around the base
            let paceVariation = Double(Int.random(in: -5 ... 5, using: &state.rng))
            let currentPace = basePace + paceVariation

            // Distance from pace: d = (segmentDuration / pace) * 500
            let segmentDistance = (segmentDuration / currentPace) * 500
            state.distance += segmentDistance

            // HR varies ±3 bpm
            let hrVariation = Int.random(in: -3 ... 3, using: &state.rng)
            let currentHR = baseHR + hrVariation

            return LiveWorkoutSample(
                id: id,
                sport: sport,
                distance: state.distance,
                time: state.elapsed,
                pace: currentPace,
                strokeRate: baseStrokeRate + Double(Int.random(in: -2 ... 2, using: &state.rng)),
                heartRateAvg: currentHR,
                date: date
            )
        }
    }

    /// Resets the generator to its initial state.
    public func reset() {
        state.withLock {
            $0.elapsed = 0
            $0.distance = 0
            $0.tick = 0
            $0.rng = SeededGenerator(seed: initialSeed)
        }
    }
}
