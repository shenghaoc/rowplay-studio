import Foundation

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
public final class DemoLiveSampleGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private let id: Int
    private let sport: Sport
    private let basePace: TimeInterval
    private let baseStrokeRate: Double
    private let baseHR: Int
    private let initialSeed: UInt64
    private var elapsed: TimeInterval
    private var distance: Double
    private var rng: SeededGenerator
    private var tick: Int

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
        self.elapsed = 0
        self.distance = 0
        self.rng = SeededGenerator(seed: seed)
        self.tick = 0
    }

    /// Returns the next sample in the sequence, advancing the workout by one segment.
    public func nextSample(at date: Date = Date()) -> LiveWorkoutSample {
        lock.lock()
        defer { lock.unlock() }

        tick += 1

        // Advance by 30 seconds per tick, matching a typical poll interval chunk
        let segmentDuration: TimeInterval = 30
        elapsed += segmentDuration

        // Pace varies ±5 sec/500m around the base
        let paceVariation = Double(Int.random(in: -5 ... 5, using: &rng))
        let currentPace = basePace + paceVariation

        // Distance from pace: d = (segmentDuration / pace) * 500
        let segmentDistance = (segmentDuration / currentPace) * 500
        distance += segmentDistance

        // HR varies ±3 bpm
        let hrVariation = Int.random(in: -3 ... 3, using: &rng)
        let currentHR = baseHR + hrVariation

        return LiveWorkoutSample(
            id: id,
            sport: sport,
            distance: distance,
            time: elapsed,
            pace: currentPace,
            strokeRate: baseStrokeRate + Double(Int.random(in: -2 ... 2, using: &rng)),
            heartRateAvg: currentHR,
            date: date
        )
    }

    /// Resets the generator to its initial state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        elapsed = 0
        distance = 0
        tick = 0
        rng = SeededGenerator(seed: initialSeed)
    }
}
